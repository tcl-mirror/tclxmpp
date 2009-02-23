# dns.tcl --
#
#       This file is part of the XMPP library. It provides support for XMPP
#       Client SRV DNS records (RFC 3920) and DNS TXT Resource Record Format
#       (XEP-0156).
#
# Copyright (c) 2006-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require dns 1.3

package provide xmpp::dns 0.1

namespace eval ::xmpp::dns {}

# ::xmpp::dns::resolveXMPPClient --
#
#       Resolve XMPP client SRV record.
#
# Arguments:
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with
#                       host-port pairs list appended.
#
# Result:
#       DNS token in asynchronous mode, or list of host-port pairs in
#       synchronous mode.

proc ::xmpp::dns::resolveXMPPClient {domain args} {
    return [eval [list resolveSRV _xmpp-client._tcp $domain] $args]
}

# ::xmpp::dns::resolveXMPPServer --
#
#       Resolve XMPP server SRV record.
#
# Arguments:
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with
#                       host-port pairs list appended.
#
# Result:
#       DNS token in asynchronous mode, or list of host-port pairs in
#       synchronous mode.

proc ::xmpp::dns::resolveXMPPServer {domain args} {
    return [eval [list resolveSRV _xmpp-server._tcp $domain] $args]
}

# ::xmpp::dns::resolveSRV --
#
#       Resolve any SRV record.
#
# Arguments:
#       srv             SRV part of DNS record.
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with
#                       host-port pairs list appended.
#
# Result:
#       DNS token in asynchronous mode, or list of host-port pairs in
#       synchronous mode.

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
        return [Resolve $name SRV \
                        [namespace code [list ProcessSRVResult $command]]]
    }
}

# ::xmpp::dns::resolveHTTPPoll --
#
#       Resolve TXT record for HTTP polling (see XEP-0025).
#
# Arguments:
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with list of
#                       HTTP-poll URLs appended.
#
# Result:
#       DNS token in asynchronous mode, or HTTP-poll URL in synchronous mode.

proc ::xmpp::dns::resolveHTTPPoll {domain args} {
    return [eval [list resolveTXT _xmppconnect _xmpp-client-httppoll $domain] \
                                  $args]
}

# ::xmpp::dns::resolveBOSH --
#
#       Resolve TXT record for BOSH (HTTP-bind, see XEP-0124 and XEP-0206)
#       connection.
#
# Arguments:
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with list of
#                       BOSH URLs appended.
#
# Result:
#       DNS token in asynchronous mode, or list of BOSH URLs in synchronous
#       mode.

proc ::xmpp::dns::resolveBOSH {domain args} {
    return [eval [list resolveTXT _xmppconnect _xmpp-client-xbosh $domain] \
                                  $args]
}

# ::xmpp::dns::resolveTXT --
#
#       Resolve TXT record.
#
# Arguments:
#       txt             Owner of the record.
#       attr            Attribute name of the record.
#       domain          Domain to resolve.
#       -command cmd    (optional) If present, resolution is made in
#                       asynchronous mode and the result is reported via
#                       callback. The supplied command is called with list of
#                       resolved names appended.
#
# Result:
#       DNS token in asynchronous mode, or list of resolved names in
#       synchronous mode.

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
        return [Resolve $name TXT \
                        [namespace code [list ProcessTXTResult $attr \
                                                               $command]]]
    }
}

# ::xmpp::dns::abort --
#
#       Abort asynchronous DNS lookup procedure.
#
# Arguments:
#       token           DNS token created in [Resolve].
#
# Result:
#       Empty string.
#
# Side effects:
#       DNS lookup is aborted, and callback is called with error.

proc ::xmpp::dns::abort {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(token)]} {
        dns::reset $state(token)
        dns::cleanup $state(token)

        ResolveCallback $token "" "" $state(command) {} "DNS lookup aborted"
    }

    return
}

# ::xmpp::dns::ProcessTXTResult --
#
#       Convert DNS result of TXT record resolution to a list of strings
#       corresponding to a specified attribute name if the resolution succeded,
#       and invoke a callback.
#
# Arguments:
#       attr            Attribute name of a TXT record.
#       command         Callback to invoke.
#       status          "ok", "error", or "abort"
#       result          List of results from DNS server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Callback procedure is called.

proc ::xmpp::dns::ProcessTXTResult {attr command status result} {
    if {[string equal $status ok]} {
        set result [TXTResultToList $attr $result]
    }
    eval $command [list $status $result]
    return
}

# ::xmpp::dns::TXTResultToList --
#
#       Convert DNS result of TXT record resolution to a list of strings
#       corresponding to a specified attribute name.
#
# Arguments:
#       attr            Attribute name of a TXT record.
#       res             List of results from DNS server.
#
# Result:
#       List of results which correspond the specified attribute name.
#
# Side effects:
#       None.

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
#
#       Convert DNS result of SRV record resolution to a list of host-port
#       pairs ordered in a way to respect priorities and weights if the
#       resolution succeded, and invoke a callback.
#
# Arguments:
#       command         Callback to invoke.
#       status          "ok", "error", or "abort"
#       result          List of results from DNS server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Callback procedure is called.


proc ::xmpp::dns::ProcessSRVResult {command status result} {
    if {[string equal $status ok]} {
        set result [SRVResultToList $result]
    }
    eval $command [list $status $result]
}

# ::xmpp::dns::SRVResultToList --
#
#       Convert DNS result of SRV record resolution to a list of host-port
#       pairs ordered in a way to respect priorities and weights.
#
# Arguments:
#       res             List of results from DNS server.
#
# Result:
#       List of host-port pairs.
#
# Side effects:
#       None.

proc ::xmpp::dns::SRVResultToList {res} {
    set results {}
    foreach reply $res {
        array unset rr1
        array set rr1 $reply
        if {![info exists rr1(rdata)]} continue

        array unset rr
        if {[catch {array set rr $rr1(rdata)}]} continue

        if {[string equal $rr(target) .]} continue

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
                                  [list $rr(target) $rr(port)]]
        }
    }

    set replies {}
    foreach hp [lsort -real -index 0 $results] {
        lappend replies [lindex $hp 1]
    }
    return $replies
}

# ::xmpp::dns::CheckNumber --
#
#       Check if the value is integer and belongs to 0..65535 interval.
#
# Arguments:
#       val             Value to check.
#
# Result:
#       1 if value is integer and fits 0..65535, 0 otherwise.
#
# Side effects:
#       None.

proc ::xmpp::dns::CheckNumber {val} {
    if {[string is integer -strict $val] && $val >= 0 && $val < 65536} {
        return 1
    } else {
        return 0
    }
}

# ::xmpp::dns::Resolve --
#
#       Synchronously or asynchronously resolve a given name of a given type.
#
# Arguments:
#       name            DNS name to resolve.
#       type            DNS record type to resolve.
#       command         (optional) If present turns asynchronous mode on and
#                       gives a command to call back.
#
# Result:
#       A token in asynchronous mode (to make abortion possible), or a DNS
#       result in synchronous mode.

proc ::xmpp::dns::Resolve {name type {command ""}} {
    variable id

    set nameservers [dns::nameservers]

    if {![string equal $command ""]} {
        if {![info exists id]} {
            set id 0
        }

        set token [namespace current]::[incr id]
        variable $token
        upvar 0 $token state

        set state(command) $command

        ResolveCallback $token $name $type $command $nameservers \
                        "No nameservers found"
        # Return token to be able to abort DNS lookup
        return $token
    }

    if {[llength $nameservers] == 0} {
        return -code error "No nameservers found"
    }

    foreach ns $nameservers {
        set token [dns::resolve $name -type $type -nameserver $ns]
        dns::wait $token

        if {[string equal [dns::status $token] ok]} {
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
#
#       Resolve a specified name of a given type using the first nameserver
#       in a list, or call back with error if nameserver list is empty.
#
# Arguments:
#       token           DNS token, created in [Resolve].
#       name            DNS name to resolve.
#       type            DNS record type to resolve.
#       command         (optional) If present turns asynchronous mode on and
#                       gives a command to call back.
#       nameservers     Nameservers list to use.
#       err             Current error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       If nameserver list is empty then the callback is invoked with error,
#       otherwise DNS lookup is started and its token is stored in a variable.

proc ::xmpp::dns::ResolveCallback {token name type command nameservers err} {
    variable $token
    upvar 0 $token state

    if {[llength $nameservers] == 0} {
        after idle $command [list error $err]
        unset state
    } else {
        set state(token) \
            [dns::resolve $name -type $type \
                                -nameserver [lindex $nameservers 0] \
                                -command [namespace code \
                                            [list ResolveCallbackStep \
                                                  $token $name $type $command \
                                                  [lrange $nameservers 1 end]]]]
    }

    return
}

# ::xmpp::dns::ResolveCallbackStep --
#
#       Check DNS server answer and if it's OK then call back, otherwise try
#       to use the next nameserver.
#
# Arguments:
#       token           DNS token, created in [Resolve].
#       name            DNS name to resolve.
#       type            DNS record type to resolve.
#       command         (optional) If present turns asynchronous mode on and
#                       gives a command to call back.
#       nameservers     Nameservers list to use.
#       dtoken          Internal DNS token to examine.
#
# Result:
#       Empty string.
#
# Side effects:
#       If DNS result is ok then the callback is invoked with status ok,
#       otherwise the next DNS lookup is started.

proc ::xmpp::dns::ResolveCallbackStep {token name type command
                                       nameservers dtoken} {
    variable $token
    upvar 0 $token state

    if {[string equal [dns::status $dtoken] ok]} {
        eval $command [list ok [dns::result $dtoken]]
        unset state
    } else {
        ResolveCallback $token $name $type $command $nameservers \
                        [dns::error $dtoken]
    }
    dns::cleanup $dtoken
    return
}

# vim:ts=8:sw=4:sts=4:et
