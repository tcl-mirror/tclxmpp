# delay.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Delayed Delivery (XEP-0091 and XEP-0203)
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::delay 0.1

namespace eval ::xmpp::delay {}

# ::xmpp::delay::exists --
#
#       Find delay element in a list and return true if it's found.
#
# Arguments:
#       xmlElements         XML elements list.
#
# Result:
#       If there's a delay elements in the given list then the result is true
#       otherwise it's false.
#
# Side effects:
#       None.

proc ::xmpp::delay::exists {xmlElements} {
    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels

        switch -- $xmlns {
            urn:xmpp:delay -
            jabber:x:delay {
                return true
            }
        }
    }
    return false
}

# ::xmpp::delay::parse --
#
#       Find delay element in a list and parse it.
#
# Arguments:
#       xmlElements         XML elements list.
#
# Result:
#       If there's a delay elements in the given list then the result is a
#       serialized list {stamp $stamp [from $from] seconds $seconds} where
#       'stamp' and 'from' are copied verbatim from the stanza and 'seconds'
#       represent number of seconds since epoch stored in the first delay
#       element. Otherwise the current time is returned. urn:xmpp:delay
#       element is preferred to jabber:x:delay one.
#
# Side effects:
#       None.

proc ::xmpp::delay::parse {xmlElements} {
    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels

        switch -- $xmlns {
            urn:xmpp:delay {
                # 2006-07-17T05:29:12Z
                # 2006-11-18T03:35:56.415699Z
                if {![regexp {(\d+)-(\d\d)-(\d\d)(T\d+:\d+:\d+)[^Z]*Z?} \
                            [::xmpp::xml::getAttr $attrs stamp] \
                            -> y m d t]} {
                    set seconds [clock seconds]
                } elseif {[catch {clock scan $y$m$d$t -gmt 1} seconds]} {
                    set seconds [clock seconds]
                }

                return [linsert $attrs end seconds $seconds]
            }
        }
    }

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels

        switch -- $xmlns {
            jabber:x:delay {
                # 20060717T05:29:12
                # 20061118T03:35:56.415699
                if {![regexp {\d+\d\d\d\dT\d+:\d+:\d+} \
                            [::xmpp::xml::getAttr $attrs stamp] \
                            stamp]} {
                    set seconds [clock seconds]
                } elseif {[catch {clock scan $stamp -gmt 1} seconds]} {
                    set seconds [clock seconds]
                }

                return [linsert $attrs end seconds $seconds]
            }
        }
    }

    return [list seconds [clock seconds]]
}

# ::xmpp::delay::create --
#
#       Create delay element using XEP-0203 or XEP-0091 (now deprecated) rules.
#
# Arguments:
#       seconds         (optional, defaults to the current time) Seconds since
#                       epoch to store in XML element.
#       -old bool       (optional, defaults to false) If true then XEP-0091 is
#                       used. If false then XEP-0203 is used.
#
# Results:
#       An XML element from XEP-0203 is created (without from attribute and
#       text cdata).
#
# Side effects:
#       None.

proc ::xmpp::delay::create {args} {
    switch -- [llength $args] {
        0 {
            set seconds [clock seconds]
            set old false
        }
        1 {
            set seconds [lindex $args 0]
            set old false
        }
        2 {
            switch -- [lindex $args 0] {
                -old {
                    set seconds [clock seconds]
                    set old [lindex $args 1]
                }
                default {
                    return -code error \
                           "Usage: ::xmpp::delay::create\
                            ?seconds? ?-old boolean?"
                }
            }
        }
        3 {
            set seconds [lindex $args 0]
            switch -- [lindex $args 1] {
                -old {
                    set old [lindex $args 2]
                }
                default {
                    return -code error \
                           "Usage: ::xmpp::delay::create\
                            ?seconds? ?-old boolean?"
                }
            }
        }
        default {
            return -code error "Usage: ::xmpp::delay::create\
                                ?seconds? ?-old boolean?"
        }
    }

    if {$old} {
        return [::xmpp::xml::create x \
                    -xmlns jabber:x:delay \
                    -attrs [list stamp \
                                 [clock format $seconds \
                                        -format %Y%m%dT%H:%M:%S \
                                        -gmt 1]]]
    } else {
        return [::xmpp::xml::create delay \
                    -xmlns urn:xmpp:delay \
                    -attrs [list stamp \
                                 [clock format $seconds \
                                        -format %Y-%m-%dT%H:%M:%SZ \
                                        -gmt 1]]]
    }
}

# vim:ts=8:sw=4:sts=4:et
