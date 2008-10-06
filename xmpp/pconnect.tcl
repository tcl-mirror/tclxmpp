#  pconnect.tcl ---
#
#       Interface to socks4/5 or https to make usage of 'socket' transparent.
#       Can also be used as a wrapper for the 'socket' command without any
#       proxy configured.
#
#  Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
#  This source file is distributed under the BSD license.
#
# $Id$

catch {package require ceptcl}
package require msgcat

package provide pconnect 0.1

namespace eval ::pconnect {
    variable packs
    array set packs {}

    namespace export register proxies socket abort
}

# ::pconnect::register --
#
#       Register proxy for connecting using pconnect::socket.
#
# Arguments:
#       proxy:          the proxy identificator (socks4, socks5, https,
#                       whatever)
#       connectCmd:     the command to call when connecting through proxy
#       abortCmd:       the command to call when aborting connection (before
#                       connection succeded)
#
# Result:
#       An empty string.
#
# Side effects:
#       Proxy $proxy is registered and can be used in pconnect::socket calls.

proc ::pconnect::register {proxy connectCmd abortCmd} {
    variable packs

    set packs($proxy) [list $connectCmd $abortCmd]
    return
}

# ::pconnect::proxies --
#
#       Return a registered proxies list (excluding an empty proxy, which is
#       assumed to be always available).
#
# Arguments:
#       None.
#
# Result:
#       A list of registered proxiy identificators (alphabetically sorted).
#
# Side effects:
#       None.

proc ::pconnect::proxies {} {
    variable packs

    return [lsort [array names packs]]
}

# ::pconnect::socket --
#
#       Client side socket through a proxy.
#
# Arguments:
#       host:            the peer address, not SOCKS server
#       port:            the peer's port number
#       args:
#           -domain      inet (default) | inet6
#           -proxy       "" (default) | socks4 | socks5 | https
#           -host        proxy hostname (required if -proxy isn't "")
#           -port        port number (required if -proxy isn't "")
#           -username    user ID
#           -password    password
#           -useragent   user agent (for HTTP proxies)
#           -command     tclProc {token status}
#                        the 'status' is any of:
#                        ok, error, timeout, network-failure,
#                         rsp_*, err_* (see socks4/5)
# Results:
#       A socket if -command is not specified or a token to make
#       possible to interrupt timed out connect.

proc ::pconnect::socket {host port args} {
    variable packs

    array set Args {-domain    inet
                    -proxy     ""
                    -host      ""
                    -port      ""
                    -username  ""
                    -password  ""
                    -useragent ""
                    -command   ""}
    array set Args $args
    set proxy $Args(-proxy)

    if {[string length $proxy] > 0 && ![info exists packs($proxy)]} {
        return -code error [::msgcat::mc "Unsupported proxy \"%s\"" $proxy]
    }

    if {[string length $proxy] > 0} {
        if {[string length $Args(-host)] > 0 && \
                [string length $Args(-port)] > 0} {
            set ahost $Args(-host)
            set aport $Args(-port)
        } else {
            return -code error [::msgcat::mc "Options \"-host\" and \"-port\"\
                                              are required"]
        }
    } else {
        set ahost $host
        set aport $port
    }

    if {[string equal $Args(-domain) inet6]} {
        if {[llength [package provide ceptcl]] == 0} {
            return -code error [::msgcat::mc "IPv6 support is not available"]
        } else {
            set sock [cep -domain inet6 -async $ahost $aport]
        }
    } else {
        set sock [::socket -async $ahost $aport]
    }

    set token [namespace current]::$sock
    fconfigure $sock -blocking 0
    fileevent $sock writable [namespace code [list Writable $token \
                                                            $ahost $aport]]

    variable $token
    upvar 0 $token state

    array set state [array get Args]
    set state(ahost) $ahost
    set state(aport) $aport
    set state(host)  $host
    set state(port)  $port
    set state(sock)  $sock

    if {[string length $state(-command)] > 0} {
        return $token
    } else {
        vwait $token\(status)

        set status $state(status)
        set sock $state(sock)
        catch {unset state}

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

# ::pconnect::abort --
#
#       Abort connection which is in progress. If a connection is already
#       established or failed then return error.
#
# Arguments:
#       token:      A control token which is returned by pconnect::socket
#
# Result:
#       An empty string or error.
#
# Side effects:
#       A connection which is establising currently is aborted. If a callback
#       procedure was supplied then it is called with error.

proc ::pconnect::abort {token} {
    variable packs
    variable $token
    upvar 0 $token state

    if {![info exists $token]} {
        return -code error \
               -errorinfo "Connection either established or failed already"
    }

    set proxy $state(-proxy)

    if {[info exists state(ptoken)]} {
        uplevel #0 [lindex $packs($proxy) 1] [list $state(ptoken)]
    } else {
        if {[string length $proxy] > 0} {
            Finish $token abort [::msgcat::mc "Connection to proxy aborted"]
        } else {
            Finish $token abort [::msgcat::mc "Connection aborted"]
        }
    }
    return
}

# ::pconnect::Writable --
#
#       A helper procedure which checks if the connection is established and
#       if it is a connection to a proxy then call a corresponding connect
#       routine. This procedure is called when an opened socket becomes
#       writable.
#
# Arguments:
#       token:      A control token which is returned by pconnect::socket
#
# Result:
#       An empty string.
#
# Side effects:
#       None.

proc ::pconnect::Writable {token ahost aport} {
    variable packs
    variable $token
    upvar 0 $token state

    set proxy $state(-proxy)
    set sock $state(sock)
    fileevent $sock writable {}

    if {[catch {fconfigure $sock -peername}]} {
        if {[string length $proxy] > 0} {
            Finish $token error [::msgcat::mc "Cannot connect to proxy %s:%s" \
                                              $ahost $aport]
        } else {
            Finish $token error [::msgcat::mc "Cannot connect to %s:%s" \
                                              $ahost $aport]
        }
    } else {
        if {[string length $proxy] > 0} {
            set state(ptoken) \
                [uplevel #0 [lindex $packs($proxy) 0] \
                         [list $sock $state(host) $state(port) \
                               -command [namespace code [list ProxyCallback \
                                                              $token]]] \
                         [GetOpts $token]]
        } else {
            Finish $token ok
        }
    }
    return
}

# ::pconnect::GetOpts --
#
#       A helper procedure which returns additional options to pass them to
#       proxy connect command.
#
# Arguments:
#       token:      A control token which is returned by pconnect::socket
#
# Result:
#       A list of options -username, -password, -useragent which were supplied
#       to pconnect::socket earlier.
#
# Side effects:
#       None.

proc ::pconnect::GetOpts {token} {
    variable $token
    upvar 0 $token state

    set opts {}
    if {[string length $state(-username)] > 0} {
        lappend opts -username $state(-username)
    }
    if {[string length $state(-password)] > 0} {
        lappend opts -password $state(-password)
    }
    if {[string length $state(-useragent)] > 0} {
        lappend opts -useragent $state(-useragent)
    }
    return $opts
}

# ::pconnect::ProxyCallback --
#
#       A helper procedure which is called as a callback by a proxy connect
#       procedure.
#
# Arguments:
#       token:      A control token which is returned by pconnect::socket
#       status:     Proxy connect status (ok or error)
#       sock:       A new TCP socket if $status equals ok or an error message
#                   if $status equals error
#
# Result:
#       An empty string.
#
# Side effects:
#       A socket in state array is updated and connection procedure is finished
#       (either with ok or error status).

proc ::pconnect::ProxyCallback {token status sock} {
    variable $token
    upvar 0 $token state

    if {[string equal $status ok]} {
        set state(sock) $sock
        Finish $token ok
    } else {
        # If $status equals to error or abort then $sock contains error message
        Finish $token $status $sock
    }
    return
}

# ::pconnect::Finish --
#
#       A helper procedure which cleans up state and calls a callback command
#       (or sets traced status variable to return back to pconnect::socket).
#
# Arguments:
#       token:      A control token which is returned by pconnect::socket
#       status:     A connection status (ok, error, or abort).
#       errormsg:   An error message (is used if status is not ok).
#
# Result:
#       An empty string.
#
# Side effects:
#       If -command option was supplied to pconnect::socket then $token state
#       variable is destroyed and callback is invoked. Otherwise status
#       variable is set making vwaiting pconnect::socket continue.

proc ::pconnect::Finish {token status {errormsg ""}} {
    variable $token
    upvar 0 $token state

    if {[string length $state(-command)]} {
        set sock $state(sock)
        set cmd $state(-command)
        catch {unset state}
        if {[string equal $status ok]} {
            uplevel #0 $cmd [list ok $sock]
        } else {
            catch {close $sock}
            uplevel #0 $cmd [list $status $errormsg]
        }
    } else {
        # Setting state(status) returns control to pconnect::socket

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

# vim:ts=8:sw=4:sts=4:et
