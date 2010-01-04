# privacy.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       Privacy Lists (XEP-0016).
#
# Copyright (c) 2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::privacy 0.1

namespace eval ::xmpp::privacy {
    namespace export register unregister requestLists requestItems sendItems \
                     setDefault setActive

    variable answer

    variable rid
    if {![info exists rid]} {
        set rid 0
    }
}

# ::xmpp::privacy::requestLists --
#
#       Request privacy lists from the user's XMPP server
#
# Arguments:
#       xlib                XMPP library token
#       -timeout timeout    Return error after the specified timeout (in
#                           milliseconds)
#       -command command    Callback to call on server reply or timeout. It
#                           must accept arguments {ok items} or
#                           {status error_xml} where status is error, abort, or
#                           timeout
#
# Result:
#       Sent XMPP IQ id.
#
# Side effects:
#       XMPP IQ stanza is sent.

proc ::xmpp::privacy::requestLists {xlib args} {
    set commands {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    variable rid
    incr rid

    set id \
        [::xmpp::sendIQ $xlib get \
                -query [::xmpp::xml::create query \
                                            -xmlns jabber:iq:privacy] \
                -command [namespace code [list ParseListsReply $rid $commands]] \
                -timeout $timeout]

    if {[llength $commands] > 0} {
        # Asynchronous mode
        return $id
    } else {
        # Synchronous mode
        variable answer
        vwait [namespace current]::answer($rid)
        foreach {status msg} $answer($rid) break
        unset answer($rid)

        switch -- $status {
            ok {
                return $msg
            }
            error {
                return -code error $msg
            }
            default {
                return -code break $msg
            }
        }
    }
}

# ::xmpp::privacy::ParseListsReply --
#
#       A helper procedure which parses server reply to a privacy lists
#       request and invokes callback.
#
# Arguments:
#       rid             A request id (is used in synchronous mode)
#       commands        A list of commands to call (it's either empty or
#                       contains a single element)
#       status          A status of the request (ok, error, abort, or timeout)
#       xml             XML element with either error message or items list
#
# Result:
#       An empty string
#
# Side effects:
#       A callback is called if specified

proc ::xmpp::privacy::ParseListsReply {rid commands status xml} {
    variable answer

    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list $status $xml]
        } else {
            set answer($rid) [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set res(items) {}
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            default {
                set res(default) [::xmpp::xml::getAttr $sattrs name]
            }
            active {
                set res(active) [::xmpp::xml::getAttr $sattrs name]
            }
            list {
                lappend res(items) [::xmpp::xml::getAttr $sattrs name]
            }
        }
    }

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list ok [array get res]]
    } else {
        set answer($rid) [list ok [array get res]]
    }
    return
}

# ::xmpp::privacy::requestItems --
#
#       Request privacy list with a specified name from the user's XMPP server
#
# Arguments:
#       xlib                XMPP library token
#       name                Privacy list name
#       -timeout timeout    Return error after the specified timeout (in
#                           milliseconds)
#       -command command    Callback to call on server reply or timeout. It
#                           must accept arguments {ok items} or
#                           {status error_xml} where status is error, abort, or
#                           timeout
#
# Result:
#       Sent XMPP IQ id.
#
# Side effects:
#       XMPP IQ stanza is sent.

proc ::xmpp::privacy::requestItems {xlib name args} {
    set commands {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    variable rid
    incr rid

    set id \
        [::xmpp::sendIQ $xlib get \
                -query [::xmpp::xml::create query \
                                -xmlns jabber:iq:privacy \
                                -subelement [::xmpp::xml::create list \
                                                    -attrs [list name $name]]] \
                -command [namespace code [list ParseItemsReply $rid $commands]] \
                -timeout $timeout]

    if {[llength $commands] > 0} {
        # Asynchronous mode
        return $id
    } else {
        # Synchronous mode
        variable answer
        vwait [namespace current]::answer($rid)
        foreach {status msg} $answer($rid) break
        unset answer($rid)

        switch -- $status {
            ok {
                return $msg
            }
            error {
                return -code error $msg
            }
            default {
                return -code break $msg
            }
        }
    }
}

# ::xmpp::privacy::ParseItemsReply --
#
#       A helper procedure which parses server reply to a privacy list
#       request and invokes callback.
#
# Arguments:
#       rid             A request id (is used in synchronous mode)
#       commands        A list of commands to call (it's either empty or
#                       contains a single element)
#       status          A status of the request (ok, error, abort, or timeout)
#       xml             XML element with either error message or items list
#
# Result:
#       An empty string
#
# Side effects:
#       A callback is called if specified. In case of success it is called
#       with ok and ordered items list without order attribute appended

proc ::xmpp::privacy::ParseItemsReply {rid commands status xml} {
    variable answer

    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list $status $xml]
        } else {
            set answer($rid) [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set items {}
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            list {
                foreach ssubel $ssubels {
                    ::xmpp::xml::split $ssubel \
                                sstag ssxmlns ssattrs sscdata sssubels

                    switch -- $sstag {
                        item {
                            set item {}
                            set order -1
                            foreach {attr val} $ssattrs {
                                switch -- $attr {
                                    order {
                                        if {[string is integer -strict $val]} {
                                            set order $val
                                        }
                                    }
                                    default {
                                        lappend item $attr $val
                                    }
                                }
                            }

                            set subitems {}
                            foreach sssubel $sssubels {
                                ::xmpp::xml::split $sssubel \
                                        ssstag sssxmlns sssattrs \
                                        ssscdata ssssubels

                                switch -- $ssstag {
                                    message -
                                    presence-in -
                                    presence-out -
                                    iq {
                                        lappend subitems $ssstag
                                    }
                                }
                            }

                            if {[llength $subitems] > 0} {
                                lappend item stanzas $subitems
                            }

                            if {$order > 0} {
                                lappend items [list $order $item]
                            }
                        }
                    }
                }

                break
            }
        }
    }

    set res {}
    foreach oi [lsort -index 0 -integer $items] {
        lappend res [lindex $oi 1]
    }

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list ok $res]
    } else {
        set answer($rid) [list ok $res]
    }
    return
}

# ::xmpp::privacy::sendItems --
#
#       Send privacy list items to the user's XMPP server
#
# Arguments:
#       xlib                XMPP library token
#       name                Privacy list name
#       items               Items to send in format
#                           {{type ... value ... action ... stanzas ...} ...}
#       -timeout timeout    Return error after the specified timeout (in
#                           milliseconds)
#       -command command    Callback to call on server reply or timeout. It
#                           must accept arguments {ok {}} or {status error_xml}
#                           where status is error, abort, or timeout
#
# Result:
#       Sent XMPP IQ id.
#
# Side effects:
#       XMPP IQ stanza is sent.

proc ::xmpp::privacy::sendItems {xlib name items args} {
    set commands {}
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set subels {}
    set order 1
    foreach item $items {
        set attrs {}
        set stanzas {}
        foreach {key val} $item {
            switch -- $key {
                type -
                value -
                action {
                    lappend attrs $key $val
                }
                stanzas {
                    foreach tag $val {
                        switch -- $tag {
                            message -
                            presence-in -
                            presence-out -
                            iq {
                                lappend stanzas [::xmpp::xml::create $tag]
                            }
                        }
                    }
                }
            }
        }
        lappend attrs order $order
        lappend subels [::xmpp::xml::create item \
                                    -attrs $attrs \
                                    -subelements $stanzas]
        incr order
    }

    variable rid
    incr rid

    set id \
        [::xmpp::sendIQ $xlib set \
                -query [::xmpp::xml::create query \
                                -xmlns jabber:iq:privacy \
                                -subelement [::xmpp::xml::create list \
                                                    -attrs [list name $name] \
                                                    -subelements $subels]] \
                -command [namespace code [list ParseSendItemsReply $rid $commands]] \
                -timeout $timeout]

    if {[llength $commands] > 0} {
        # Asynchronous mode
        return $id
    } else {
        # Synchronous mode
        variable answer
        vwait [namespace current]::answer($rid)
        foreach {status msg} $answer($rid) break
        unset answer($rid)

        switch -- $status {
            ok {
                return $msg
            }
            error {
                return -code error $msg
            }
            default {
                return -code break $msg
            }
        }
    }
}

# ::xmpp::privacy::ParseSendItemsReply --
#
#       A helper procedure which parses server reply to a privacy list
#       set request and invokes callback.
#
# Arguments:
#       rid             A request id (is used in synchronous mode)
#       commands        A list of commands to call (it's either empty or
#                       contains a single element)
#       status          A status of the request (ok, error, abort, or timeout)
#       xml             XML element with either error message or items list
#
# Result:
#       An empty string
#
# Side effects:
#       A callback is called if specified.

proc ::xmpp::privacy::ParseSendItemsReply {rid commands status xml} {
    variable answer

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    } else {
        set answer($rid) [list $status $xml]
    }
    return
}

# ::xmpp::privacy::setDefault --
#
#       Set default privacy list name.
#
# Arguments:
#       xlib                XMPP library token
#       -name    name       Default privacy list name, if missing then no
#                           default privacy list is set
#       -timeout timeout    Return error after the specified timeout (in
#                           milliseconds)
#       -command command    Callback to call on server reply or timeout. It
#                           must accept arguments {ok {}} or {status error_xml}
#                           where status is error, abort, or timeout
#
# Result:
#       Sent XMPP IQ id.
#
# Side effects:
#       XMPP IQ stanza is sent.

proc ::xmpp::privacy::setDefault {xlib args} {
    set commands {}
    set timeout 0
    set attrs {}

    foreach {key val} $args {
        switch -- $key {
            -name {
                set attrs [list name $val]
            }
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    variable rid
    incr rid

    set id \
        [::xmpp::sendIQ $xlib set \
                -query [::xmpp::xml::create query \
                                -xmlns jabber:iq:privacy \
                                -subelement [::xmpp::xml::create default \
                                                    -attrs $attrs]] \
                -command [namespace code [list ParseDefaultReply $rid $commands]] \
                -timeout $timeout]

    if {[llength $commands] > 0} {
        # Asynchronous mode
        return $id
    } else {
        # Synchronous mode
        variable answer
        vwait [namespace current]::answer($rid)
        foreach {status msg} $answer($rid) break
        unset answer($rid)

        switch -- $status {
            ok {
                return $msg
            }
            error {
                return -code error $msg
            }
            default {
                return -code break $msg
            }
        }
    }
}

# ::xmpp::privacy::ParseDefaultReply --
#
#       A helper procedure which parses server reply to a default privacy list
#       set request and invokes callback.
#
# Arguments:
#       rid             A request id (is used in synchronous mode)
#       commands        A list of commands to call (it's either empty or
#                       contains a single element)
#       status          A status of the request (ok, error, abort, or timeout)
#       xml             XML element with either error message or items list
#
# Result:
#       An empty string
#
# Side effects:
#       A callback is called if specified.

proc ::xmpp::privacy::ParseDefaultReply {rid commands status xml} {
    variable answer

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    } else {
        set answer($rid) [list $status $xml]
    }
    return
}

# ::xmpp::privacy::setActive --
#
#       Set active privacy list name.
#
# Arguments:
#       xlib                XMPP library token
#       -name    name       Active privacy list name, if missing then no
#                           active privacy list is set
#       -timeout timeout    Return error after the specified timeout (in
#                           milliseconds)
#       -command command    Callback to call on server reply or timeout. It
#                           must accept arguments {ok {}} or {status error_xml}
#                           where status is error, abort, or timeout
#
# Result:
#       Sent XMPP IQ id.
#
# Side effects:
#       XMPP IQ stanza is sent.

proc ::xmpp::privacy::setActive {xlib args} {
    set commands {}
    set timeout 0
    set attrs {}

    foreach {key val} $args {
        switch -- $key {
            -name {
                set attrs [list name $val]
            }
            -timeout {
                set timeout $val
            }
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    variable rid
    incr rid

    set id \
        [::xmpp::sendIQ $xlib set \
                -query [::xmpp::xml::create query \
                                -xmlns jabber:iq:privacy \
                                -subelement [::xmpp::xml::create active \
                                                    -attrs $attrs]] \
                -command [namespace code [list ParseActiveReply $rid $commands]] \
                -timeout $timeout]

    if {[llength $commands] > 0} {
        # Asynchronous mode
        return $id
    } else {
        # Synchronous mode
        variable answer
        vwait [namespace current]::answer($rid)
        foreach {status msg} $answer($rid) break
        unset answer($rid)

        switch -- $status {
            ok {
                return $msg
            }
            error {
                return -code error $msg
            }
            default {
                return -code break $msg
            }
        }
    }
}

# ::xmpp::privacy::ParseActiveReply --
#
#       A helper procedure which parses server reply to an active privacy list
#       set request and invokes callback.
#
# Arguments:
#       rid             A request id (is used in synchronous mode)
#       commands        A list of commands to call (it's either empty or
#                       contains a single element)
#       status          A status of the request (ok, error, abort, or timeout)
#       xml             XML element with either error message or items list
#
# Result:
#       An empty string
#
# Side effects:
#       A callback is called if specified.

proc ::xmpp::privacy::ParseActiveReply {rid commands status xml} {
    variable answer

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
    } else {
        set answer($rid) [list $status $xml]
    }
    return
}

# ::xmpp::privacy::register --
#
#       Register handler to process privacy list pushes..
#
# Arguments:
#       -command cmd    (optional) Command to call when privacy list push is
#                       arrived. The result of the command is sent back.
#                       It must be either {result {}}, or {error type
#                       condition}, or empty string if the application will
#                       reply to the request separately.
#                       The command's arguments are xlib, from, xml, and
#                       optional parameters -to, -id, -lang.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP privacy lists callback is registered.

proc ::xmpp::privacy::register {args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::iq::register get query jabber:iq:privacy \
                         [namespace code [list ParseRequest $commands]]
    return
}

# ::xmpp::privacy::ParseRequest --
#
#       A helper procedure which is called on any incoming privacy list push.
#       It either calls a command specified during registration or simply
#       returns result (if there weren't any command).
#
# Arguments:
#       commands            A list of commands to call (only the first one
#                           will be invoked).
#       xlib                XMPP token where request was received.
#       from                JID of user who sent the request.
#       xml                 Request XML element.
#       args                optional arguments (-lang, -to, -id).
#
# Result:
#       Either {result, {}}, or {error type condition}, or empty string, if
#       the application desided to reply later.
#
# Side effects:
#       Side effects of the called command.

proc ::xmpp::privacy::ParseRequest {commands xlib from xml args} {
    # -to attribute contains the own JID, so check from JID to prevent
    # malicious users to pretend they perform roster push
    set to [::xmpp::xml::getAttr $args -to]

    if {![string equal $from ""] && \
            ![::xmpp::jid::equal $from $to] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::stripResource $to]] && \
            ![::xmpp::jid::equal $from [::xmpp::jid::server $to]]} {

        return [list error cancel service-unavailable]
    }

    if {[llength $commands] > 0} {
        ::xmpp::xml::split $xml tag xmlns attrs cdata subels

        foreach subel $subels {
            ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

            switch -- $stag {
                list {
                    set name [::xmpp::xml::getAttr $sattrs name]
                    break
                }
            }
        }
        if {[info exists name]} {
            return [uplevel #0 [lindex $commands 0] [list $xlib $from $name] \
                                                    $args]
        } else {
            return [list error modify bad-request]
        }
    } else {
        return [list result {}]
    }
}

# ::xmpp::privacy::unregister --
#
#       Unregister handler which used to answer XMPP privacy list pushes..
#
# Arguments:
#       None.
#
# Result:
#       Empty string.
#
# Side effects:
#       XMPP privacy lists callback is unregistered.

proc ::xmpp::privacy::unregister {} {
    ::xmpp::iq::unregister get query jabber:iq:privacy

    return
}

# vim:ts=8:sw=4:sts=4:et
