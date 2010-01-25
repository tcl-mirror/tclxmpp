# register.tcl --
#
#       This file is a part of the XMPP library. It implements support for
#       In-Band Registration (XEP-0077).
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::register 0.1

namespace eval ::xmpp::register {
    namespace export request submit

    # Register fields (see XEP-0077)

    array set labels [list username [::msgcat::mc "Username"] \
                           nick     [::msgcat::mc "Nickname"] \
                           password [::msgcat::mc "Password"] \
                           name     [::msgcat::mc "Full name"] \
                           first    [::msgcat::mc "First name"] \
                           last     [::msgcat::mc "Last name"] \
                           email    [::msgcat::mc "E-mail"] \
                           address  [::msgcat::mc "Address"] \
                           city     [::msgcat::mc "City"] \
                           state    [::msgcat::mc "State"] \
                           zip      [::msgcat::mc "Zip"] \
                           phone    [::msgcat::mc "Phone"] \
                           url      [::msgcat::mc "URL"] \
                           date     [::msgcat::mc "Date"] \
                           misc     [::msgcat::mc "Misc"] \
                           text     [::msgcat::mc "Text"] \
                           key      [::msgcat::mc "Key"]]
}

# ::xmpp::register::request --

proc ::xmpp::register::request {xlib jid args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
        }
    }

    return [::xmpp::sendIQ $xlib get \
                    -query [::xmpp::xml::create query \
                                    -xmlns jabber:iq:register] \
                    -to $jid \
                    -command [namespace code [list ParseForm $commands]]]
}

# ::xmpp::register::submit --

proc ::xmpp::register::submit {xlib jid fields args} {
    set old false
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -old {
                set old $val
            }
            -command {
                set commands [list $val]
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
                                    -xmlns jabber:iq:register \
                                    -subelements $subels] \
                    -to $jid \
                    -command [namespace code [list SubmitResult $commands]]]
}

# ::xmpp::register::remove --

proc ::xmpp::register::remove {xlib jid args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
        }
    }

    return [::xmpp::sendIQ $xlib set \
                    -query [::xmpp::xml::create query \
                                    -xmlns jabber:iq:register \
                                    -subelement [::xmpp::xml::create remove]] \
                    -to $jid \
                    -command [namespace code [list SubmitResult $commands]]]
}

# ::xmpp::register::password --

proc ::xmpp::register::password {xlib username password args} {
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command {
                set commands [list $val]
            }
        }
    }

    set subels [list [::xmpp::xml::create username -cdata $username] \
                     [::xmpp::xml::create password -cdata $password]]

    return [::xmpp::sendIQ $xlib set \
                    -query [::xmpp::xml::create query \
                                    -xmlns jabber:iq:register \
                                    -subelements $subels] \
                    -command [namespace code [list SubmitResult $commands]]]
}

# ::xmpp::register::ParseForm --

proc ::xmpp::register::ParseForm {commands status xml} {
    if {[llength $commands] == 0} {
        return
    }

    if {![string equal $status ok]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break

    if {[string equal $type form]} {
        set fields [::xmpp::data::parseForm $form]
        set old false
    } else {
        set fields [ParseFields $subels]
        set old true
    }

    uplevel #0 [lindex $commands 0] [list $status $fields -old $old]
    return
}

# ::xmpp::register::ParseFields --

proc ::xmpp::register::ParseFields {xmlElements} {
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
                switch -- $tag {
                    key -
                    registered {
                        set type hidden
                    }
                    password {
                        set type text-private
                    }
                    default {
                        set type text-single
                    }
                }

                if {[info exists labels($tag)]} {
                    set label $labels($tag)
                } else {
                    set label ""
                }

                lappend res field \
                        [list $tag $type $label "" false {} [list $cdata] {}]
            }
        }
    }

    return $res
}

# ::xmpp::register::FillFields --

proc ::xmpp::register::FillFields {fields} {
    set res {}
    foreach {var values} $fields {
        lappend res [::xmpp::xml::create $var -cdata [lindex $values 0]]
    }
    return $res
}

# ::xmpp::register::SubmitResult --

proc ::xmpp::register::SubmitResult {commands status xml} {
    if {[llength $commands] == 0} {
        return
    }

    if {![string equal $status error]} {
        uplevel #0 [lindex $commands 0] [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break

    if {[string equal $type form]} {
        set status continue
        set fields [::xmpp::data::parseForm $form]
    } else {
        set fields $xml
    }

    uplevel #0 [lindex $commands 0] [list $status $fields]
    return
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
