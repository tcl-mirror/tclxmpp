# negotiate.tcl --
#
#       This file is a part of the XMPP library. It implements support for
#       feature negotiation (XEP-0020).
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp

package provide xmpp::negotiate 0.1

namespace eval ::xmpp::negotiate {
    ::xmpp::iq::register get feature http://jabber.org/protocol/feature-neg \
                         ::xmpp::negotiate::ParseQuery
}

# ::xmpp::negotiate::register --

proc ::xmpp::negotiate::register {feature command} {
    variable CallBack

    set CallBack($feature) $command
}

# ::xmpp::negotiate::unregister --

proc ::xmpp::negotiate::unregister {feature} {
    variable CallBack

    catch {unset CallBack($feature)}
}

# ::xmpp::negotiate::sendOptions --

proc ::xmpp::negotiate::sendOptions {xlib to feature options args} {
    set command #
    foreach {key val} $args {
        switch -- $key {
            -command {
                set command $val
            }
        }
    }

    set opts {}
    foreach o $options {
        lappend opts "" $o
    }

    set fields [::xmpp::data::formField field -var $feature \
                                              -type list-single \
                                              -options $opts]
    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create feature \
                        -xmlns http://jabber.org/protocol/feature-neg \
                        -subelement [::xmpp::data::form $fields]] \
        -to $to \
        -command [namespace code [list RecvOptionsResponse $xlib $to $command]]
}

# ::xmpp::negotiate::RecvOptionsResponse --

proc ::xmpp::negotiate::RecvOptionsResponse {xlib jid command status xml} {
    variable tmp

    if {![string equal $status ok]} {
        uplevel #0 $command [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break
    set fields [::xmpp::data::parseSubmit $form]

    uplevel #0 $command [list ok $fields]
    return
}

# ::xmpp::negotiate::sendRequest --

proc ::xmpp::negotiate::sendRequest {xlib to feature args} {
    set command #
    foreach {key val} $args {
        switch -- $key {
            -command {
                set command $val
            }
        }
    }

    set fields [list $feature {}]

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create feature \
                        -xmlns http://jabber.org/protocol/feature-neg \
                        -subelement [::xmpp::data::submitForm $fields]] \
        -to $to \
        -command [namespace code [list RecvRequestResponse $xlib $to $command]]
}

# ::xmpp::negotiate::RecvRequestResponse --

proc ::xmpp::negotiate::RecvRequestResponse {xlib jid command status xml} {
    variable tmp

    if {![string equal $status ok]} {
        uplevel #0 $command [list $status $xml]
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach {type form} [::xmpp::data::findForm $subels] break
    set fields [::xmpp::data::parseForm $form]

    uplevel #0 $command [list ok $fields]
    return
}

# ::xmpp::negotiate::ParseQuery --

proc ::xmpp::negotiate::ParseQuery {xlib from xml args} {
    variable CallBack

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set lang [::xmpp::xml::getAttr $args -lang en]

    foreach {type form} [::xmpp::data::findForm $subels] break

    switch -- $type {
        form {
            # Options offer

            set sfields {}
            set fields [::xmpp::data::parseForm $form]

            foreach {tag item} $fields {
                if {![string equal $tag field]} continue

                foreach {var type label desc required options values} $item {
                    break
                }

                switch -- $type {
                    hidden {
                        lappend sfields $var $values
                    }
                    default {
                        if {![info exists CallBack($var)]} continue

                        set vals [eval $CallBack($var) \
                                       [list $xlib $from $options] $args]

                        if {[llength $vals] > 0} {
                            lappend sfields $var $vals
                        }
                    }
                }
            }

            if {[llength $sfields] > 0} {
                return [list result \
                             [::xmpp::xml::create feature \
                                    -xmlns \
                                     http://jabber.org/protocol/feature-neg \
                                    -subelement \
                                     [::xmpp::data::submitForm $sfields]]]
            }
        }
        submit {
            # Options request

            set sfields {}
            set fields [::xmpp::data::parseSubmit $form]

            foreach {tag item} $fields {
                if {![string equal $tag field]} continue

                foreach {var type label values} $item break

                if {![info exists CallBack($var)]} continue

                set opts [eval $CallBack($var) [list $xlib $from {}] $args]

                if {[llength $opts] == 0} continue

                set oopts {}
                foreach o $opts {
                    lappend oopts "" $o
                }
                lappend sfields [::xmpp::data::formField field \
                                        -var $var \
                                        -options $oopts]
            }

            if {[llength $sfields] > 0} {
                return [list result \
                             [::xmpp::xml::create feature \
                                    -xmlns \
                                     http://jabber.org/protocol/feature-neg \
                                    -subelement [::xmpp::data::form $sfields]]]
            }
        }
    }

    return [list error cancel feature-not-implemented]
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
