#  dns.tcl --
#  
#      This file is part of the XMPP library. It provides support for
#      Jabber Client SRV DNS records (RFC 3920) and
#      DNS TXT Resource Record Format (XEP-0156).
#      
#  Copyright (c) 2006-2008 Sergei Golovan <sgolovan@nes.ru>
#  
# $Id$
#
#  SYNOPSIS
#      ::xmpp::dns::resolveXMPPClient domain ?-command cmd?
#      ::xmpp::dns::resolveXMPPServer domain ?-command cmd?
#      ::xmpp::dns::resolveSRV        srv domain ?-command cmd?
#  RETURNS list of {hostname port} pairs
#
#  SYNOPSIS
#      ::xmpp::dns::resolveHTTPPoll domain ?-command cmd?
#      ::xmpp::dns::resolveBOSH     domain ?-command cmd?
#      ::xmpp::dns::resolveTXT      txt domain ?-command cmd?
#  RETURNS URL for HTTP-poll connect method (XEP-0025)
#

package require dns

if {$::tcl_platform(platform) == "windows"} {
    package require registry
}

package provide xmpp::dns 0.1

namespace eval ::xmpp::dns {}

# ::xmpp::dns::resolveXMPPClient --

proc ::xmpp::dns::resolveXMPPClient {domain args} {
    return [eval {resolveSRV _xmpp-client._tcp $domain} $args]
}

# ::xmpp::dns::resolveXMPPServer --

proc ::xmpp::dns::resolveXMPPServer {domain args} {
    return [eval {resolveSRV _xmpp-server._tcp $domain} $args]
}

# ::xmpp::dns::resolveSRV --

proc ::xmpp::dns::resolveSRV {srv domain args} {
    foreach {key val} $args {
        switch -- $key {
            -command { set command $val }
        }
    }

    set name $srv.$domain

    if {![info exists command]} {
        return [SRVResultToList [Resolve $name SRV]]
    } else {
        Resolve $name SRV [namespace code [list ProcessSRVResult $command]]
    }
}

# ::xmpp::dns::resolveTXT --

proc ::xmpp::dns::resolveTXT {txt attr domain args} {
    foreach {key val} $args {
        switch -- $key {
            -command { set command $val }
        }
    }

    set name $txt.$domain

    if {![info exists command]} {
        return [TXTResultToList $attr [Resolve $name TXT]]
    } else {
        Resolve $name TXT [namespace code [list ProcessTXTResult $attr $command]]
    }
}

# ::xmpp::dns::ProcessTXTResult --

proc ::xmpp::dns::ProcessTXTResult {attr command status result} {
    if {$status == "ok"} {
        set result [TXTResultToList $attr $result]
    }
    eval $command {$status $result}
}

# ::xmpp::dns::TXTResultToList --

proc ::xmpp::dns::TXTResultToList {attr res} {
    set results {}
    foreach reply $res {
        array set rr $reply
        if {[regexp "$attr=(.*)" $rr(rdata) -> url]} {
            lappend results $url
        }
    }
    return $results
}

# ::xmpp::dns::ProcessSRVResult --

proc ::xmpp::dns::ProcessSRVResult {command status result} {
    if {$status == "ok"} {
        set result [SRVResultToList $result]
    }
    eval $command {$status $result}
}

# ::xmpp::dns::SRVResultToList --

proc ::xmpp::dns::SRVResultToList {res} {
    set results {}
    foreach reply $res {
        array unset rr1
        array set rr1 $reply
        if {![info exists rr1(rdata)]} continue

        array unset rr
        if {[catch { array set rr $rr1(rdata) }]} continue

        if {$rr(target) == "."} continue

        if {[info exists rr(priority)] && [CheckNumber $rr(priority)] && \
                [info exists rr(weight)] && [CheckNumber $rr(weight)] && \
                [info exists rr(port)] && [CheckNumber $rr(port)] && \
                [info exists rr(target)]} {
            if {$rr(weight) == 0} {
                set n 0
            } else {
                set n [expr {($rr(weight) + 1) * rand()}]
            }
            lappend results [list [expr {$rr(priority) * 65536 - $n}] \
                                  $rr(target) $rr(port)]
        }
    }

    set replies {}
    foreach hp [lsort -real -index 0 $results] {
        lappend replies [list [lindex $hp 1] [lindex $hp 2]]
    }
    return $replies
}

# ::xmpp::dns::CheckNumber --

proc ::xmpp::dns::CheckNumber {val} {
    if {[string is integer -strict $val] && $val >= 0 && $val < 65536} {
        return 1
    } else {
        return 0
    }
}

# ::xmpp::dns::Resolve --

proc ::xmpp::dns::Resolve {name type {command ""}} {
    set nameservers [GetNameservers]

    if {$command != ""} {
        ResolveCallback $name $type $command $nameservers
        return
    }

    if {[llength $nameservers] == 0} {
        return -code error "no nameservers found"
    }

    foreach ns $nameservers {
        set token [dns::resolve $name -type $type -nameserver $ns]
        dns::wait $token

        if {[dns::status $token] == "ok"} {
            set res [dns::result $token]
            dns::cleanup $token
            return $res
        } else {
            set err [dns::error $token]
            dns::cleanup $token
        }
    }
    return -code error $err
}

# ::xmpp::dns::ResolveCallback --

proc ::xmpp::dns::ResolveCallback {name type command nameservers \
                                            {err "no nameservers found"}} {
    if {[llength $nameservers] == 0} {
        eval $command [list error $err]
    } else {
        dns::resolve $name -type $type -nameserver [lindex $nameservers 0] \
            -command [namespace code [list ResolveCallbackStep \
                           $name $type $command [lrange $nameservers 1 end]]]
    }
}

# ::xmpp::dns::ResolveCallbackStep --

proc ::xmpp::dns::ResolveCallbackStep {name type command nameservers token} {
    if {[dns::status $token] == "ok"} {
        eval $command [list ok [dns::result $token]]
    } else {
        ResolveCallback $name $type $command $nameservers [dns::error $token]
    }
    dns::cleanup $token
}

# ::xmpp::dns::GetNameservers --

proc ::xmpp::dns::GetNameservers {} {
    global tcl_platform

    switch -- $tcl_platform(platform) {
        unix {
            set resolv "/etc/resolv.conf"
            if {![file readable $resolv]} {
                return {127.0.0.1}
            } else {
                set fd [open $resolv]
                set lines [split [read $fd] "\r\n"]
                close $fd
                set ns {}
                foreach line $lines {
                    if {[regexp {^nameserver\s+(\S+)} $line -> ip]} {
                        lappend ns $ip
                    }
                }
                if {$ns == {}} {
                    return {127.0.0.1}
                } else {
                    return $ns
                }
            }
        }
        windows {
            set services_key \
                "HKEY_LOCAL_MACHINE\\system\\CurrentControlSet\\Services"
            set win9x_key "$services_key\\VxD\\MSTCP"
            set winnt_key "$services_key\\TcpIp\\Parameters"
            set interfaces_key "$winnt_key\\Interfaces"

            # Windows 9x
            if {![catch { registry get $win9x_key "NameServer" } ns]} {
                return [join [split $ns ,] " "]
            }

            # Windows NT/2000/XP
            if {![catch { registry get $winnt_key "NameServer" } ns] && \
                    $ns != {}} {
                return [join [split $ns ,] " "]
            }
            if {![catch { registry get $winnt_key "DhcpNameServer" } ns] && \
                    $ns != {}} {
                return $ns
            }
            foreach key [registry keys $interfaces_key] {
                if {![catch {
                          registry get "$interfaces_key\\$key" \
                                       "NameServer"
                      } ns] && $ns != {}} {
                    return [join [split $ns ,] " "]
                }
                if {![catch {
                          registry get "$interfaces_key\\$key" \
                                       "DhcpNameServer"
                      } ns] && $ns != {}} {
                    return $ns
                }
            }
            return {}
        }
    }
}

# vim:ts=8:sw=4:sts=4:et
