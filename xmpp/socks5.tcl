# socks5.tcl ---
#
#       Package for using the SOCKS5 method for connecting TCP sockets.
#       Some code plus idee from Kerem 'Waster_' Hadimli.
#       Made from RFC 1928.
#
# Copyright (c) 2000 Kerem Hadimli
# Copyright (c) 2003-2007 Mats Bengtsson
# Copyright (c) 2007-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require pconnect
package require ip
package require msgcat

package provide pconnect::socks5 0.1

namespace eval ::pconnect::socks5 {
    namespace export connect

    # Constants:
    # ver:                Socks version
    # nomatchingmethod:   No matching methods
    # cmd_connect:        Connect command
    # rsv:                Reserved
    # atyp_*:             Address type
    # auth_*:             Authorication version
    variable const
    array set const {
        ver                 \x05
        auth_no             \x00
        auth_gssapi         \x01
        auth_userpass       \x02
        nomatchingmethod    \xFF
        cmd_connect         \x01
        cmd_bind            \x02
        rsv                 \x00
        atyp_ipv4           \x01
        atyp_domainname     \x03
        atyp_ipv6           \x04
    }

    variable msg
    array set msg [list \
        1   [::msgcat::mc "General SOCKS server failure"] \
        2   [::msgcat::mc "Connection not allowed by ruleset"] \
        3   [::msgcat::mc "Network unreachable"] \
        4   [::msgcat::mc "Host unreachable"] \
        5   [::msgcat::mc "Connection refused by destination host"] \
        6   [::msgcat::mc "TTL expired"] \
        7   [::msgcat::mc "Command not supported"] \
        8   [::msgcat::mc "Address type not supported"]]

    variable debug 0

    ::pconnect::register socks5 \
                         [namespace current]::connect \
                         [namespace current]::abort
}

# ::pconnect::socks5::connect --
#
#       Negotiates with a SOCKS server.
#
# Arguments:
#       sock        an open socket to the SOCKS5 server
#       addr        the peer address, not SOCKS5 server
#       port        the peer's port number
#       args
#               -command    tclProc {status socket}
#               -username   username
#               -password   password
#               -timeout    millisecs (default 60000)
#
# Results:
#       The connect socket or error if no -command, else a connection token.
#
# Side effects:
#       Socket is prepared for data transfer.
#       If -command specified, the callback tclProc is called with
#       status ok and socket or error and error message.

proc ::pconnect::socks5::connect {sock addr port args} {
    variable msg
    variable const

    # Initialize the state variable, an array.  We'll return the
    # name of this array as the token for the transaction.

    set token [namespace current]::$sock
    variable $token
    upvar 0 $token state

    Debug $token 2 "$addr $port $args"

    array set state {
        -password ""
        -timeout  60000
        -username ""
        -command  ""
        async     0
        auth      0
        bnd_addr  ""
        bnd_port  ""
        state     ""
        status    ""
    }
    array set state [list addr $addr \
                          port $port \
                          sock $sock]
    array set state $args

    if {[string length $state(-username)] || \
            [string length $state(-password)]} {
        set state(auth) 1
    }
    if {![string equal $state(-command) ""]} {
        set state(async) 1
    }
    if {$state(auth)} {
        set methods  "$const(auth_no)$const(auth_userpass)"
    } else {
        set methods  "$const(auth_no)"
    }
    set nmethods [binary format c [string length $methods]]

    fconfigure $sock -translation {binary binary} -blocking 0
    fileevent $sock writable {}

    Debug $token 2 "send: ver nmethods methods"

    # Request authorization methods
    if {[catch {
        puts -nonewline $sock "$const(ver)$nmethods$methods"
        flush $sock
    } err]} {
        catch {close $sock}
        if {$state(async)} {
            after idle $state(-command) \
                  [list error [::msgcat::mc "Failed to send SOCKS5\
                                             authorization methods request"]]
            Free $token
            return
        } else {
            Free $token
            return -code error [::msgcat::mc "Failed to send SOCKS5\
                                              authorization methods request"]
        }
    }

    # Setup timeout timer.
    if {$state(-timeout) > 0} {
        set state(timeoutid) \
            [after $state(-timeout) [namespace code [list Timeout $token]]]
    }

    fileevent $sock readable \
              [namespace code [list ResponseMethod $token]]

    if {$state(async)} {
        return $token
    } else {
        # We should not return from this proc until finished!
        vwait $token\(status)

        set status $state(status)
        set sock $state(sock)

        Free $token

        if {[string equal $status ok]} {
            return $sock
        } else {
            catch {close $sock}
            if {[string equal $status abort]} {
                return -code break $sock
            } else {
                return -code error $sock
            }
        }
    }
}

# ::pconnect::socks5::abort --
#
#       Abort proxy negotiation.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A proxy negotiation is finished with error.

proc ::pconnect::socks5::abort {token} {
    Finish $token abort [::msgcat::mc "SOCKS5 proxy negotiation aborted"]
    return
}

# ::pconnect::socks5::ResponseMethod --
#
#       Receive the reply from a proxy and choose authorization method.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished with error or continues with chosen
#       method.

proc ::pconnect::socks5::ResponseMethod {token} {
    variable $token
    variable const
    upvar 0 $token state

    Debug $token 2 ""

    set sock $state(sock)

    if {[catch {read $sock 2} data] || [eof $sock]} {
        Finish $token error [::msgcat::mc "Failed to read SOCKS5\
                                     authorization methods response"]
        return
    }
    set serv_ver ""
    set method $const(nomatchingmethod)
    binary scan $data cc serv_ver smethod
    Debug $token 2 "serv_ver=$serv_ver, smethod=$smethod"

    if {![string equal $serv_ver 5]} {
        Finish $token error [::msgcat::mc "Incorrect SOCKS5 server version"]
        return
    }

    if {[string equal $smethod 0]} {
        # Now, request address and port.
        Request $token
    } elseif {[string equal $smethod 2]} {
        # User/Pass authorization required
        if {$state(auth) == 0} {
            Finish $token error [::msgcat::mc "SOCKS5 server authorization required"]
            return
        }

        # Username & Password length (binary 1 byte)
        set ulen [binary format c [string length $state(-username)]]
        set plen [binary format c [string length $state(-password)]]

        Debug $token 2 "send: auth_userpass ulen -username plen -password"
        if {[catch {
            puts -nonewline $sock \
                 "$const(auth_userpass)$ulen$state(-username)$plen$state(-password)"
            flush $sock
        } err]} {
            Finish $token error [::msgcat::mc "Failed to send SOCKS5\
                                         authorization request"]
            return
        }

        fileevent $sock readable \
                  [namespace code [list ResponseAuth $token]]
    } else {
        Finish $token error [::msgcat::mc "Unsupported SOCKS5 authorization method"]
        return
    }

    return
}

# ::pconnect::socks5::ResponseAuth --
#
#       Receive the authorization reply from a proxy.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished with error or continues with address and
#       port request.

proc ::pconnect::socks5::ResponseAuth {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    set sock $state(sock)

    if {[catch {read $sock 2} data] || [eof $sock]} {
        Finish $token error [::msgcat::mc "Failed to read SOCKS5\
                                     authorization response"]
        return
    }

    set auth_ver -1
    set status -1
    binary scan $data cc auth_ver status
    Debug $token 2 "auth_ver=$auth_ver, status=$status"

    if {![string equal $auth_ver 1]} {
        Finish $token error [::msgcat::mc "Unsupported SOCKS5 authorization method"]
        return
    }
    if {![string equal $status 0]} {
        Finish $token error [::msgcat::mc "SOCKS5 server authorization failed"]
        return
    }

    # Now, request address and port.
    Request $token
    return
}

# ::pconnect::socks5::Request --
#
#       Request connect to specified address and port.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished with error or continues with address and
#       port request.

proc ::pconnect::socks5::Request {token} {
    variable $token
    variable const
    upvar 0 $token state

    Debug $token 2 ""

    set sock $state(sock)

    # Network byte-ordered port (2 binary-bytes, short)
    set bport [binary format S $state(port)]

    # Figure out type of address given to us.
    if {[ip::version $state(addr)] == 4} {
        Debug $token 2 "ipv4"

        # IPv4 numerical address.
        set atyp_addr_port $const(atyp_ipv4)
        foreach i [split [ip::normalize $state(addr)] .] {
            append atyp_addr_port [binary format c $i]
        }
        append atyp_addr_port $bport
    } elseif {[ip::version $state(addr)] == 6} {
        Debug $token 2 "ipv6"

        # IPv6 numerical address.
        set atyp_addr_port $const(atyp_ipv6)
        foreach i [split [ip::normalize $state(addr)] :] {
            append atyp_addr_port [binary format S 0x$i]
        }
        append atyp_addr_port $bport
    } else {
        Debug $token 2 "domainname"

        # Domain name.
        # Domain length (binary 1 byte)
        set dlen [binary format c [string length $state(addr)]]
        set atyp_addr_port "$const(atyp_domainname)$dlen$state(addr)$bport"
    }

    # We send request for connect
    Debug $token 2 "send: ver cmd_connect rsv atyp_domainname dlen addr port"
    set aconst "$const(ver)$const(cmd_connect)$const(rsv)"
    if {[catch {
        puts -nonewline $sock "$aconst$atyp_addr_port"
        flush $sock
    } err]} {
        Finish $token error [::msgcat::mc "Failed to send SOCKS5 connection request"]
        return
    }

    fileevent $sock readable \
              [namespace code [list Response $token]]
    return
}

# ::pconnect::socks5::Response --
#
#       Receive the final reply from a proxy and finish the negotiations.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished with either success or error.

proc ::pconnect::socks5::Response {token} {
    variable msg
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    set sock $state(sock)
    fileevent $sock readable {}

    # Start by reading ver+cmd+rsv.
    if {[catch {read $sock 3} data] || [eof $sock]} {
        Finish $token error [::msgcat::mc "Failed to read SOCKS5 connection response"]
        return
    }
    set serv_ver ""
    set rep ""
    binary scan $data ccc serv_ver rep rsv

    if {![string equal $serv_ver 5]} {
        Finish $token error [::msgcat::mc "Incorrect SOCKS5 server version"]
        return
    }
    if {$rep == 0} {
        # ok
    } elseif {[info exists msg($rep)]} {
        Finish $token error $msg($rep)
        return
    } else {
        Finish $token error [::msgcat::msg "Unknown SOCKS5 server error"]
        return
    }

    # Now parse the variable length atyp+addr+host.
    if {[catch {ParseAtypAddr $token addr port} err]} {
        Finish $token error $err
        return
    }

    # Store in our state array.
    set state(bnd_addr) $addr
    set state(bnd_port) $port

    # And finally let the client know that the bytestream is set up.
    Finish $token ok
    return
}

# ::pconnect::socks5::ParseAtypAddr --
#
#       Receive and parse destination address type and IP or name.
#
# Arguments:
#       token       A connection token.
#       addrVar     A variable for destination address.
#       portVar     A variable for destination port.
#
# Result:
#       An empty string or error if address and port can't be parsed.
#
# Side effects:
#       The address type and IP or name is read from the socket.

proc ::pconnect::socks5::ParseAtypAddr {token addrVar portVar} {
    variable $token
    variable const
    upvar 0 $token state
    upvar 1 $addrVar addr
    upvar 1 $portVar port

    Debug $token 2 ""

    set sock $state(sock)

    # Start by reading atyp.
    if {[catch {read $sock 1} data] || [eof $sock]} {
        return -code error [::msgcat::mc "Failed to read SOCKS5\
                                          destination address type"]
    }
    set atyp ""
    binary scan $data c atyp
    Debug $token 2 "atyp=$atyp"

    # Treat the three address types in order.
    switch -- $atyp {
        1 {
            # IPv4

            if {[catch {read $sock 6} data] || [eof $sock]} {
                return -code error [::msgcat::mc "Failed to read SOCKS5\
                                                  destination IPv4 address\
                                                  and port"]
            }
            binary scan $data ccccS i0 i1 i2 i3 port
            set addr {}
            foreach n [list $i0 $i1 $i2 $i3] {
                # Translate to unsigned!
                lappend addr [expr {$n & 0xff}]
            }
            set addr [join $addr .]
            # Translate to unsigned!
            set port [expr {$port & 0xffff}]
        }
        3 {
            # Domain

            if {[catch {read $sock 1} data] || [eof $sock]} {
                return -code error [::msgcat::mc "Failed to read SOCKS5\
                                                  destination domain\
                                                  length"]
            }
            binary scan $data c len
            Debug $token 2 "len=$len"
            set len [expr {$len & 0xff}]
            if {[catch {read $sock $len} data] || [eof $sock]} {
                return -code error [::msgcat::mc "Failed to read SOCKS5\
                                                  destination domain"]
            }
            set addr $data
            Debug $token 2 "addr=$addr"
            if {[catch {read $sock 2} data] || [eof $sock]} {
                return -code error [::msgcat::mc "Failed to read SOCKS5\
                                                  destination port"]
            }
            binary scan $data S port
            # Translate to unsigned!
            set port [expr {$port & 0xffff}]
            Debug $token 2 "port=$port"
        }
        4 {
            # IPv6

            if {[catch {read $sock 18} data] || [eof $sock]} {
                return -code error [::msgcat::mc "Failed to read SOCKS5\
                                                  destination IPv6 address\
                                                  and port"]
            }
            binary scan $data SSSSSSSSS s0 s1 s2 s3 s4 s5 s6 s7 s8 port
            set addr {}
            foreach n [list $s0 $s1 $s2 $s3 $s4 $s5 $s6 $s7 $s8] {
                # Translate to unsigned!
                lappend addr [format %x [expr {$n & 0xffff}]]
            }
            set addr [join $addr :]
            # Translate to unsigned!
            set port [expr {$port & 0xffff}]
        }
        default {
            return -code error [::msgcat::mc "Unknown SOCKS5 destination\
                                              address type"]
        }
    }
}

proc ::pconnect::socks5::GetIpAndPort {token} {
    variable $token
    upvar 0 $token state
    return [list $state(bnd_addr) $state(bnd_port)]
}

# ::pconnect::socks5::Timeout --
#
#       This proc is called in case of timeout.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A proxy negotiation is finished with error.

proc ::pconnect::socks5::Timeout {token} {
    Finish $token timeout [::msgcat::mc "SOCKS5 negotiation timed out"]
    return
}

# ::pconnect::socks5::Free --
#
#       Frees a connection token.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A connection token and its state informationa are destroyed.

proc ::pconnect::socks5::Free {token} {
    variable $token
    upvar 0 $token state

    catch {after cancel $state(timeoutid)}
    catch {unset state}
}

# ::pconnect::socks5::Finish --
#
#       Finishes a negotiation process.
#
# Arguments:
#       token       A connection token.
#       errormsg    (optional) error message.
#
# Result:
#       An empty string.
#
# Side effects:
#       If connection is asynchronous then a callback is executed.
#       Otherwise state(status) is set to allow ::pconnect::socks5::connect
#       to return with either success or error.

proc ::pconnect::socks5::Finish {token status {errormsg ""}} {
    variable $token
    upvar 0 $token state

    catch {after cancel $state(timeoutid)}

    Debug $token 2 "status=$status, errormsg=$errormsg"

    if {$state(async)} {
        # In case of asynchronous connection we do the cleanup.
        set command $state(-command)
        set sock $state(sock)
        Free $token
        if {[string equal $status ok]} {
            uplevel #0 $command [list ok $sock]
        } else {
            catch {close $sock}
            uplevel #0 $command [list $status $errormsg]
        }
    } else {
        # Otherwise we trigger state(status).
        if {[string equal $status ok]} {
            set state(status) ok
        } else {
            catch {close $state(sock)}
            set state(sock) $errormsg
            set state(status) $status
        }
    }
    return
}

# ::pconnect::socks5::Debug --
#
#       Prints debug information.
#
# Arguments:
#       token       Token.
#       level       Debug level.
#       str         Debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::pconnect::socks5::debug variable is not less than num.

proc ::pconnect::socks5::Debug {token level str} {
    variable debug

    if {$debug >= $level} {
        puts "[lindex [info level -1] 0] $token: $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
