# https.tcl --
#
#       Package for using the HTTP CONNECT (it is a common method for
#       tunnelling HTTPS traffic, so the name is https) method for
#       connecting TCP sockets. Only client side.
#
# Copyright (c) 2007-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require base64
package require SASL::NTLM 1.0
package require pconnect 0.1
package require msgcat

package provide pconnect::https 0.1

namespace eval ::pconnect::https {
    namespace export connect abort

    variable debug 0

    ::pconnect::register https [namespace code connect] \
                               [namespace code abort]
}

# ::pconnect::https::connect --
#
#       Negotiates with a HTTPS proxy server.
#
# Arguments:
#       sock        an open socket token to the proxy server
#       addr        the peer address, not the proxy server
#       port        the peer port number
#       args
#               -command    tclProc {status socket}
#               -username   userid
#               -password   password
#               -useragent  useragent
#               -timeout    millisecs (default 60000)
#
# Results:
#       The connect socket or error if no -command, else control token
#       (to be able to abort connect process).
#
# Side effects:
#       Socket is prepared for data transfer.
#       If -command specified, the callback tclProc is called with
#       status ok and socket or error and error message.

proc ::pconnect::https::connect {sock addr port args} {
    variable auth

    set token [namespace current]::$sock
    variable $token
    upvar 0 $token state

    Debug $token 2 "sock=$sock, addr=$addr, port=$port, args=$args"

    array set state {
        -command   ""
        -timeout   60000
        -username  ""
        -password  ""
        -useragent ""
        async      0
        status     ""
    }
    array set state [list addr $addr \
                          port $port \
                          sock $sock]
    array set state $args

    if {[string length $state(-command)] > 0} {
        set state(async) 1
    }

    if {[catch {set state(peer) [fconfigure $sock -peername]}]} {
        catch {close $sock}
        if {$state(async)} {
            after idle $state(-command) \
                  [list error [::msgcat::mc "Failed to conect to HTTPS proxy"]]
            Free $token
            return $token
        } else {
            Free $token
            return -code error [::msgcat::mc "Failed to conect to HTTPS proxy"]
        }
    }

    PutsConnectQuery $token

    fileevent $sock readable \
              [namespace code [list Readable $token]]

    # Setup timeout timer.
    if {$state(-timeout) > 0} {
        set state(timeoutid) \
            [after $state(-timeout) [namespace code [list Timeout $token]]]
    }

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

# ::pconnect::https::abort --
#
#       This proc aborts proxy negotiation.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       A proxy negotiation is finished with error.

proc ::pconnect::https::abort {token} {
    Finish $token abort [::msgcat::mc "HTTPS proxy negotiation aborted"]
    return
}

# ::pconnect::https::Readable --
#
#       Receive the first reply from a proxy and either finish the
#       negotiations or prepare to autorization process at the proxy.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       An empty string.
#
# Side effects:
#       The negotiation is finished or the next turn is started.

proc ::pconnect::https::Readable {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    fileevent $state(sock) readable {}
    set code [ReadProxyAnswer $token]

    if {$code >= 200 && $code < 300} {
        # Success
        while {[string length [gets $state(sock)]]} {}
        Finish $token ok
        return
    } elseif {$code != 407} {
        # Failure
        Finish $token error $state(result)
        return
    } else {
        # Authorization required
        set content_length -1
        set method basic
        while {[string length [set header [gets $state(sock)]]]} {
            Debug $token 2 "$header"
            switch -- [HttpHeaderName $header] {
                proxy-authenticate {
                    if {[string equal -length 4 [HttpHeaderBody $header] \
                                                "NTLM"]} {
                        set method ntlm
                    }
                }
                content-length {
                    set content_length [HttpHeaderBody $header]
                }
            }
        }

        ReadProxyJunk $token $content_length
        close $state(sock)

        set state(sock) \
            [socket -async [lindex $state(peer) 0] [lindex $state(peer) 2]]

        fileevent $state(sock) writable \
                  [namespace code [list Authorize $token $method]]
    }

    return
}

# ::pconnect::https::Authorize --
#
#       Start the authorization procedure.
#
# Arguments:
#       token       A connection token.
#       method      (basic or ntlm) authorization method.
#
# Result:
#       Empty string.
#
# Side effects:
#       Authorization is started.

proc ::pconnect::https::Authorize {token method} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "$method"

    fileevent $state(sock) writable {}

    switch -- $method {
        ntlm {
            AuthorizeNtlmStep1 $token
        }
        default {
            AuthorizeBasicStep1 $token
        }
    }

    return
}

# https::AuthorizeBasicStep1 --
#
#       The first step of basic authorization procedure: send authorization
#       credentials to a socket.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Authorization info is sent to a socket.

proc ::pconnect::https::AuthorizeBasicStep1 {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    set auth \
        [string map {\n {}} \
             [base64::encode \
                  [encoding convertto "$state(-username):$state(-password)"]]]

    PutsConnectQuery $token "Basic $auth"

    fileevent $state(sock) readable \
              [namespace code [list AuthorizeBasicStep2 $token]]

    return
}

# ::pconnect::https::AuthorizeBasicStep2 --
#
#       The second step of basic authorization procedure: receive and
#       analyze server reply.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Server reply is received from a socket.

proc ::pconnect::https::AuthorizeBasicStep2 {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    fileevent $state(sock) readable {}

    set code [ReadProxyAnswer $token]

    if {$code >= 200 && $code < 300} {
        # Success
        while {[string length [gets $state(sock)]]} { }
        Finish $token ok
        return
    } else {
        # Failure
        Finish $token error $state(result)
        return
    }

    return
}

# ::pconnect::https::AuthorizeNtlmStep1 --
#
#       The first step of NTLM authorization procedure: send NTLM
#       message 1 to a socket.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Authorization info is sent to a socket.

proc ::pconnect::https::AuthorizeNtlmStep1 {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    set message1 \
        [string map {\n {}} \
                [base64::encode [::SASL::NTLM::CreateGreeting "" ""]]]

    Debug $token 2 "NTLM $message1"

    PutsConnectQuery $token "NTLM $message1"

    fileevent $state(sock) readable \
              [namespace code [list AuthorizeNtlmStep2 $token]]

    return
}

# ::pconnect::https::AuthorizeNtlmStep2 --
#
#       The first step of basic authorization procedure: send authorization
#       credentials to a socket.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Authorization info is sent to a socket.

proc ::pconnect::https::AuthorizeNtlmStep2 {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    fileevent $state(sock) readable {}

    set code [ReadProxyAnswer $token]

    if {$code >= 200 && $code < 300} {
        # Success
        while {[string length [gets $state(sock)]]} { }
        Finish $token ok
        return
    } elseif {$code != 407} {
        # Failure
        Finish $token error $state(result)
        return
    }

    set content_length -1
    set message2 ""
    while {![string equal [set header [gets $state(sock)]] ""]} {
        Debug $token 2 "$header"
        switch -- [HttpHeaderName $header] {
            proxy-authenticate {
                set body [HttpHeaderBody $header]
                if {[string equal -length 5 $body "NTLM "]} {
                    set message2 [string trim [string range $body 5 end]]
                }
            }
            content-length {
                set content_length [HttpHeaderBody $header]
            }
        }
    }

    ReadProxyJunk $token $content_length

    Debug $token 2 "NTLM $message2"

    array set challenge [::SASL::NTLM::Decode [base64::decode $message2]]

    # if username is domain/username or domain\username
    # then set domain and username
    set username $state(-username)
    regexp {(\w+)[\\/](.*)} $username -> domain username

    set message3 \
        [string map {\n {}} \
                [base64::encode \
                        [::SASL::NTLM::CreateResponse $challenge(domain) \
                                                      [info hostname]    \
                                                      $username          \
                                                      $state(-password)  \
                                                      $challenge(nonce)  \
                                                      $challenge(flags)]]]
    Debug $token 2 "NTLM $message3"

    PutsConnectQuery $token "NTLM $message3"

    fileevent $state(sock) readable \
              [namespace code [list AuthorizeNtlmStep3 $token]]

    return
}

# ::pconnect::https::AuthorizeNtlmStep3 --
#
#       The third step of NTLM authorization procedure: receive and
#       analyze server reply.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Server reply is received from a socket.

proc ::pconnect::https::AuthorizeNtlmStep3 {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    fileevent $state(sock) readable {}

    set code [ReadProxyAnswer $token]

    if {$code >= 200 && $code < 300} {
        # Success
        while {[string length [gets $state(sock)]]} { }
        Finish $token ok
        return
    } else {
        # Failure
        Finish $token error $state(result)
        return
    }

    return
}

# ::pconnect::https::PutsConnectQuery --
#
#       Sends CONNECT query to a proxy server.
#
# Arguments:
#       token       A connection token.
#       auth        (optional) A proxy authorization string.
#
# Result:
#       Empty string.
#
# Side effects:
#       Some info is sent to a proxy.

proc ::pconnect::https::PutsConnectQuery {token {auth ""}} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "$auth"

    fconfigure $state(sock) -buffering line -translation auto

    puts $state(sock) "CONNECT $state(addr):$state(port) HTTP/1.0"
    puts $state(sock) "Proxy-Connection: keep-alive"
    if {[string length $state(-useragent)]} {
        puts $state(sock) "User-Agent: $state(-useragent)"
    }
    if {[string length $auth]} {
        puts $state(sock) "Proxy-Authorization: $auth"
    }
    puts $state(sock) ""
    return
}

# ::pconnect::https::ReadProxyAnswer --
#
#       Reads the first line of a proxy answer with a result code.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       The HTTP result code.
#
# Side effects:
#       Status line is read form a socket.
#       Variable state(result) is set to a just read line.

proc ::pconnect::https::ReadProxyAnswer {token} {
    variable $token
    upvar 0 $token state

    Debug $token 2 ""

    fconfigure $state(sock) -buffering line -translation auto

    set state(result) [gets $state(sock)]
    set code [lindex [split $state(result) { }] 1]
    if {[string is integer -strict $code]} {
        return $code
    } else {
        # Invalid code
        return 0
    }
}

# ::pconnect::https::ReadProxyJunk --
#
#       Reads the body part of a proxy answer.
#
# Arguments:
#       token       A connection token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Some info is read from a socket and discarded.

proc ::pconnect::https::ReadProxyJunk {token length} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "$length"

    fconfigure $state(sock) -buffering none -translation binary
    if {$length != -1} {
        read $state(sock) $length
    } else {
        read $state(sock)
    }
    return
}

# ::pconnect::https::HttpHeaderName --
#
#       Returns HTTP header name (converted to lowercase).
#
# Arguments:
#       header      A HTTP header.
#
# Result:
#       A header name.
#
# Side effects
#       None.

proc ::pconnect::https::HttpHeaderName {header} {
    set hlist [split $header ":"]
    return [string tolower [lindex $hlist 0]]
}

# ::pconnect::https::HttpHeaderBody --
#
#       Returns HTTP header body.
#
# Arguments:
#       header      A HTTP header.
#
# Result:
#       A header body.
#
# Side effects
#       None.

proc ::pconnect::https::HttpHeaderBody {header} {
    set hlist [split $header ":"]
    set body [join [lrange $hlist 1 end] ":"]
    return [string trim $body]
}

# ::pconnect::https::Timeout --
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

proc ::pconnect::https::Timeout {token} {
    Finish $token abort [::msgcat::mc "HTTPS proxy negotiation timed out"]
    return
}

# ::pconnect::https::Free --
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

proc ::pconnect::https::Free {token} {
    variable $token
    upvar 0 $token state

    catch {after cancel $state(timeoutid)}
    catch {unset state}
    return
}

# ::pconnect::https::Finish --
#
#       Finishes a negotiation process.
#
# Arguments:
#       token       A connection token.
#       status      ok, abort, or error
#       errormsg    (optional) error message.
#
# Result:
#       An empty string.
#
# Side effects:
#       If connection is asynchronous then a callback is executed.
#       Otherwise state(status) is set to allow ::pconnect::https::connect
#       to return with either success or error.

proc ::pconnect::https::Finish {token status {errormsg ""}} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "status=$status, errormsg=$errormsg"

    catch {after cancel $state(timeoutid)}

    if {$state(async)} {
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

# ::pconnect::https::Debug --
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
#       ::pconnect::https::debug variable is not less than num.

proc ::pconnect::https::Debug {token level str} {
    variable debug

    if {$debug >= $level} {
        puts "[lindex [info level -1] 0] $token: $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
