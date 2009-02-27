# disco.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Service Discovery (XEP-0030) and Service Discovery Extensions
#       (XEP-0128)
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::disco 0.1

namespace eval ::xmpp::disco {}

# ::xmpp::disco::new --

proc ::xmpp::disco::new {xlib args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(xlib) $xlib
    set state(cache) {}
    set state(size) 200

    foreach {key val} $args {
        switch -- $key {
            -cachesize {
                set state(size) $val
            }
            -infocommand {
                ::xmpp::iq::RegisterIQ \
                        $xlib get * http://jabber.org/protocol/disco#info \
                        [namespace code [list ParseInfoRequest $token $val]]
            }
            -itemscommand {
                ::xmpp::iq::RegisterIQ \
                        $xlib get * http://jabber.org/protocol/disco#items \
                        [namespace code [list ParseItemsRequest $token $val]]
            }
            default {
                unset state
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    return $token
}

# ::xmpp::disco::free --

proc ::xmpp::disco::free {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::iq::UnregisterIQ $xlib set * http://jabber.org/protocol/disco#info
    ::xmpp::iq::UnregisterIQ $xlib set * http://jabber.org/protocol/disco#items

    unset state
    return
}

# ::xmpp::disco::requestInfo --

proc ::xmpp::disco::requestInfo {token jid args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    set node ""
    set commands {}
    set cache 0

    foreach {key val} $args {
        switch -- $key {
            -node {
                set node $val
            }
            -command {
                set commands [list $val]
            }
            -cache {
                if {[string is true -strict $val]} {
                    set cache 1
                } elseif {![string is false -strict $val]} {
                    return -code error \
                           -errorcode [::msgcat::mc "Illegal option \"%s\" value \"%s\",\
                                                     boolean expected" $key $val]
                }
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {$cache} {
        if {[llength $commands] == 0} return

        set idx [lsearch -exact $state(cache) [list info $jid $node]]
        if {$idx >= 0} {
            set result [lindex $state(cache) $idx]
            after idle [list uplevel #0 [lindex $commands 0] \
                                        [lrange $result 1 end]]
            return
        }
    }

    if {[string equal $node ""]} {
        set attrs {}
    } else {
        set attrs [list node $node]
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create query \
                        -xmlns http://jabber.org/protocol/disco#info \
                        -attrs $attrs] \
        -to $jid \
        -command [namespace code [list ParseInfo \
                                       $token $jid $node $cache $commands]]
    return
}

# ::xmpp::disco::ParseInfo --

proc ::xmpp::disco::ParseInfo {token jid node cache commands status xml} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set identities {}
    set features {}
    set extras {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            identity {
                lappend identities $sattrs
            }
            feature {
                lappend features [::xmpp::xml::getAttr $sattrs var]
            }
            default {
                lassign [::xmpp::data::findForm [list $subel]] type form
                if {[string equal $type result]} {
                    lappend extras [::xmpp::data::parseResult $form]
                }
            }
        }
    }

    if {$cache} {
        lappend state(cache) \
                [list [list info $jid $node] \
                      ok \
                      [list $identities $features $extras]]

        if {[llength $state(cache)] > $state(size)} {
            set state(cache) [lrange $state(cache) 1 end]
        }
    }

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] \
                   [list ok [list $identities $features $extras]]
    }

    return
}

# ::xmpp::disco::requestItems --

proc ::xmpp::disco::requestItems {token jid args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    set node ""
    set commands {}
    set cache 0

    foreach {key val} $args {
        switch -- $key {
            -node {
                set node $val
            }
            -command {
                set commands [list $val]
            }
            -cache {
                if {[string is true -strict $val]} {
                    set cache 1
                } elseif {![string is false -strict $val]} {
                    return -code error \
                           -errorcode [::msgcat::mc "Illegal option \"%s\" value \"%s\",\
                                                     boolean expected" $key $val]
                }
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {$cache} {
        if {[llength $commands] == 0} return

        set idx [lsearch -exact $state(cache) [list items $jid $node]]
        if {$idx >= 0} {
            set result [lindex $state(cache) $idx]
            after idle [list uplevel #0 [lindex $commands 0] \
                                        [lrange $result 1 end]]
            return
        }
    }

    if {[string equal $node ""]} {
        set attrs {}
    } else {
        set attrs [list node $node]
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create query \
                        -xmlns http://jabber.org/protocol/disco#items \
                        -attrs $attrs] \
        -to $jid \
        -command [namespace code [list ParseItems \
                                       $token $jid $node $cache $commands]]
    return
}

# ::xmpp::disco::ParseItems --

proc ::xmpp::disco::ParseItems {token jid node cache commands status xml} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set items {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            item {
                set item [list jid [::xmpp::xml::getAttr $sattrs jid]]
                if {[::xmpp::xml::isAttr $sattrs node]} {
                    lappend item node [::xmpp::xml::getAttr $sattrs node]
                }
                if {[::xmpp::xml::isAttr $sattrs name]} {
                    lappend item name [::xmpp::xml::getAttr $sattrs name]
                }
                lappend items $item
            }
        }
    }

    if {$cache} {
        lappend state(cache) [list [list items $jid $node] ok $items]

        if {[llength $state(cache)] > $state(size)} {
            set state(cache) [lrange $state(cache) 1 end]
        }
    }

    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list ok $items]
    }

    return
}

# ::xmpp::disco::ParseInfoRequest --

proc ::xmpp::disco::ParseInfoRequest {token command xlib from xml args} {
    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set node [::xmpp::xml::getAttr $attrs node]
    set lang [::xmpp::xml::getAttr $args -lang en]

    set result [uplevel #0 $command [list $xlib $from $node $lang]]

    set status [lindex $result 0]

    if {![string equal $status result]} {
        return $result
    }

    set identities [lindex $result 1]
    set features   [lindex $result 2]
    set extras     [lindex $result 3]

    set restags {}
    foreach identity $identities {
        lappend restags [::xmpp::xml::create identity -attrs $identity]
    }
    foreach feature $features {
        lappend restags [::xmpp::xml::create feature -attrs [list var $feature]]
    }
    foreach extra $extras {
        lappend restags [::xmpp::data::resultForm $extra]
    }

    return [list result [::xmpp::xml::create query \
                                -xmlns http://jabber.org/protocol/disco#info \
                                -subelements $restags]]
}

# ::xmpp::disco::ParseItemsRequest --

proc ::xmpp::disco::ParseItemsRequest {token command xlib from xml args} {
    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set node [::xmpp::xml::getAttr $attrs node]
    set lang [::xmpp::xml::getAttr $args -lang en]

    set result [uplevel #0 $command [list $xlib $from $node $lang]]

    set status [lindex $result 0]

    if {![string equal $status result]} {
        return $result
    }

    set items [lindex $result 1]

    set restags {}
    foreach item $items {
        lappend restags [::xmpp::xml::create item -attrs $item]
    }

    return [list result [::xmpp::xml::create query \
                                -xmlns http://jabber.org/protocol/disco#items \
                                -subelements $restags]]
}

# ::xmpp::disco::publishItems --

proc ::xmpp::disco::publishItems {token node items args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    set commands {}
    foreach {key val} $args {
        switch -- {
            -command {
                set commands [list $val]
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set tags {}
    foreach item $items {
        lappend tags [::xmpp::xml::create item -attrs $item]
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create query \
                        -xmlns http://jabber.org/protocol/disco#publish \
                        -attrs [list node $node] \
                        -subelements $items] \
        -command [list [namespace current]::PublishItemsResult $commands]
}

# ::xmpp::disco::publishItemsResult --

proc ::xmpp::disco::PublishItemsResult {commands status xml} {
    if {[llength $commands] > 0} {
        uplevel #0 [lindex $commands 0] [list $res $child]
    }
    return
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
