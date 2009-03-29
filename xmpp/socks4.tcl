# socks4.tcl ---
#
#       Package for using the SOCKS4a method for connecting TCP sockets.
#       Only client side.
#
# Copyright (c) 2007  Mats Bengtsson
# Copyright (c) 2007-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require pconnect
package require msgcat

package provide pconnect::socks4 0.1

namespace eval ::pconnect::socks4 {
    namespace export connect

    variable const
    array set const {
        ver            \x04
        cmd_connect    \x01
        cmd_bind       \x02
        rsp_granted    \x5a
        rsp_failure    \x5b
        rsp_errconnect \x5c
        rsp_erruserid  \x5d
    }

    variable msg
    array set msg [list \
        91  [::msgcat::mc "Request rejected or failed"] \
        92  [::msgcat::mc "Server cannot reach client's identd"] \
        93  [::msgcat::mc "Client's identd could not confirm the userid"]]

    variable debug 0

    ::pconnect::register socks4 \
                         [namespace current]::connect \
                         [namespace current]::abort
}

# ::pconnect::socks4::connect --
#
#       Negotiates with a SOCKS server.
#
# Arguments:
#       sock        an open socket to the SOCKS server
#       addr        the peer address, not SOCKS server
#       port        the peer's port number
#       args
#               -command    tclProc {token status}
#               -username   userid
#               -timeout    millisecs (default 60000)
#
# Results:
#       The connect socket or error if no -command, else a connection token.
#
# Side effects:
#       Socket is prepared for data transfer.
#       If -command specified, the callback tclProc is called with
#       status ok and socket or error and error message.

proc ::pconnect::socks4::connect {sock addr port args} {
    variable const

    set token [namespace current]::$sock
    variable $token
    upvar 0 $token state

    array set state {
        -command    ""
        -timeout    60000
        -username   ""
        async       0
        bnd_addr    ""
        bnd_port    ""
        status      ""
    }
    array set state [list addr $addr \
                          port $port \
                          sock $sock]
    array set state $args

    if {![string equal $state(-command) ""]} {
        set state(async) 1
    }

    # Network byte-ordered port (2 binary-bytes, short)
    set bport [binary format S $port]

    # This corresponds to IP address 0.0.0.x, with x nonzero.
    set bip \x00\x00\x00\x01

    set bdata "$const(ver)$const(cmd_connect)$bport$bip"
    append bdata "$state(-username)\x00$addr\x00"

    fconfigure $sock -translation binary -blocking 0
    fileevent $sock writable {}

    if {[catch {
        puts -nonewline $sock $bdata
        flush $sock
    } err]} {
        catch {close $sock}
        if {$state(async)} {
            after idle $state(-command) \
                  [list error [::msgcat::mc "Failed to send SOCKS4a request"]]
            Free $token
            return
        } else {
            Free $token
            return -code error [::msgcat::mc "Failed to send SOCKS4a request"]
        }
    }

    # Setup timeout timer.
    if {$state(-timeout) > 0} {
        set state(timeoutid) \
            [after $state(-timeout) [namespace code [list Timeout $token]]]
    }

    fileevent $sock readable \
              [namespace code [list Response $token]]

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

# ::pconnect::socks4::abort --
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

proc ::pconnect::socks4::abort {token} {
    Finish $token abort [::msgcat::mc "SOCKS4a proxy negotiation aborted"]
    return
}

# ::pconnect::socks4::Response --
#
#       Receive the reply from a proxy and finish the negotiations.
#
# Arguments:
#       token            A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished with either success or error.

proc ::pconnect::socks4::Response {token} {
    variable $token
    upvar 0 $token state
    variable const
    variable msg

    Debug $token 2 ""

    set sock $state(sock)
    fileevent $sock readable {}

    # Read and parse status.
    if {[catch {read $sock 2} data] || [eof $sock]} {
        Finish $token error [::msgcat::mc "Failed to read SOCKS4a response"]
        return
    }
    binary scan $data cc null status
    if {![string equal $null 0]} {
        Finish $token error [::msgcat::mc "Incorrect SOCKS4a server version"]
        return
    }
    if {$status == 90} {
        # ok
    } elseif {[info exists msg($status)]} {
        Finish $token error $msg($status)
        return
    } else {
        Finish $token error [::msgcat::mc "Unknown SOCKS4a server error"]
        return
    }

    # Read and parse port (2 bytes) and ip (4 bytes).
    if {[catch {read $sock 6} data] || [eof $sock]} {
        Finish $token error [::msgcat::mc "Failed to read SOCKS4a\
                                     destination address"]
        return
    }
    binary scan $data ccccS i0 i1 i2 i3 port
    set addr {}
    foreach n [list $i0 $i1 $i2 $i3] {
        # Translate to unsigned!
        lappend addr [expr {$n & 0xff}]
    }
    # Translate to unsigned!
    set port [expr {$port & 0xffff}]

    set state(bnd_addr) [join $addr .]
    set state(bnd_port) $port

    Finish $token ok
    return
}

# ::pconnect::socks4::Timeout --
#
#       This proc is called in case of timeout.
#
# Arguments:
#       token            A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A proxy negotiation is finished with error.

proc ::pconnect::socks4::Timeout {token} {
    Finish $token abort [::msgcat::mc "SOCKS4a proxy negotiation timed out"]
    return
}

# ::pconnect::socks4::Free --
#
#       Frees a connection token.
#
# Arguments:
#       token            A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A connection token and its state informationa are destroyed.

proc ::pconnect::socks4::Free {token} {
    variable $token
    upvar 0 $token state

    catch {after cancel $state(timeoutid)}
    catch {unset state}
    return
}

# ::pconnect::socks4::Finish --
#
#       Finishes a negotiation process.
#
# Arguments:
#       token            A connection token.
#       errormsg    (optional) error message.
#
# Result:
#       An empty string.
#
# Side effects:
#       If connection is asynchronous then a callback is executed.
#       Otherwise state(status) is set to allow ::pconnect::socks4::connect
#       to return with either success or error.

proc ::pconnect::socks4::Finish {token status {errormsg ""}} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "status=$status, errormsg=$errormsg"

    catch {after cancel $state(timeoutid)}

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

# ::pconnect::socks4::Debug --
#
#       Prints debug information.
#
# Arguments:
#       token       Token.
#       num         Debug level.
#       str         Debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::pconnect::socks4::debug variable is not less than num.

proc ::pconnect::socks4::Debug {token level str} {
    variable debug

    if {$debug >= $level} {
        puts "[lindex [info level -1] 0] $token: $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
