# search.tcl --
#
#       This file is a part of the XMPP library. It implements support for
#       Jabber search (XEP-0055).
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::search 0.1

namespace eval ::xmpp::search {
    namespace export request submit

    # Search fields (see XEP-0055)

    array set labels [list jid   [::msgcat::mc "Jabber ID"] \
                           first [::msgcat::mc "First Name"] \
                           last  [::msgcat::mc "Last Name"] \
                           nick  [::msgcat::mc "Nickname"] \
                           email [::msgcat::mc "E-mail"]]
}

# ::xmpp::search::request --

proc ::xmpp::search::request {xlib jid args} {
    set command #
    foreach {key val} $args {
        switch -- $key {
            -command {
                set command $val
            }
        }
    }

    return [::xmpp::sendIQ $xlib get \
                    -query [::xmpp::xml::create query \
                                    -xmlns jabber:iq:search] \
                    -to $jid \
                    -command [namespace code [list ParseForm $command]]]
}

# ::xmpp::search::submit --

proc ::xmpp::search::submit {xlib jid fields args} {
    set old false
    set command #
    foreach {key val} $args {
        switch -- $key {
            -old {
                set old $val
            }
            -command {
                set command $val
            }
        }
    }

    if {!$old} {
        set subels [list [::xmpp::data::submitForm $fields]]
    } else {
        set subels [FillFields $fields]
    }

    return [::xmpp::sendIQ $xlib set \
                    -query [::xmpp::xml::create query \
                                    -xmlns jabber:iq:search \
                                    -subelements $subels] \
                    -to $jid \
                    -command [namespace code [list ParseResult $command]]]
}

# ::xmpp::search::ParseForm --

proc ::xmpp::search::ParseForm {command status xml} {
    if {![string equal $status ok]} {
        uplevel #0 $command [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break

    if {[string equal $type form]} {
        set fields [::xmpp::data::parseForm $form]
        set old false
    } else {
        set fields [ParseFields $items]
        set old true
    }

    uplevel #0 $command [list $status $fields -old $old]
    return
}

# ::xmpp::search::ParseFields --

proc ::xmpp::search::ParseFields {xmlElements} {
    variable labels

    set res {}
    foreach xml $xmlElements {
        ::xmpp::xml::split $xml tag xmlns attrs cdata subels

        switch -- $tag {
            instructions {
                set res [linsert $res 0 instructions $cdata]
            }
            x {}
            default {
                if {[info exists labels($tag)]} {
                    set label $labels($tag)
                } else {
                    set label $tag
                }

                lappend res field \
                        [list $tag text-single $label "" false {} [list $cdata] {}]
            }
        }
    }

    return $res
}

# ::xmpp::search::FillFields --

proc ::xmpp::search::FillFields {fields} {
    set res {}
    foreach {var values} $fields {
        lappend res [::xmpp::xml::create $var -cdata [lindex $values 0]]
    }
    return $res
}

# ::xmpp::search::ParseResult --

proc ::xmpp::search::ParseResult {command status xml} {
    if {![string equal $status ok]} {
        uplevel #0 $command [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break

    if {[string equal $type result]} {
        set fields [::xmpp::data::parseResult $form]
    } else {
        set fields [ParseLegacyItems $subels]
    }

    uplevel #0 $command [list $status $fields]
    return
}

# ::xmpp::search::ParseLegacyItems --

proc ::xmpp::search::ParseItems {items} {
    variable labels

    set res {}
    set reported(jid) $labels(jid)

    foreach item $items {
        ::xmpp::xml::split $item tag xmlns attrs cdata subels

        switch -- $tag {
            item {
                set itemjid [::xmpp::xml::getAttr $attrs jid]
                set fields [list jid $itemjid]

                foreach field $subels {
                    ::xmpp::xml::split $field stag sxmlns sattrs scdata ssubels
                    lappend fields $stag $scdata
                    if {[info exists labels($stag)]} {
                        set reported($stag) $labels($stag)
                    } else {
                        set reported($stag) ""
                    }
                }
            }
        }
        lappend res item $fields
    }

    return [linsert $res 0 reported [array get $reported]]
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
