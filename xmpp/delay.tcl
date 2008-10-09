# delay.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Delayed Delivery (XEP-0091 and XEP-0203)
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::delay 0.1

namespace eval ::xmpp::delay {}

# ::xmpp::delay::parse --
#
#       Find delay element in a list and parse it.
#
# Arguments:
#       xmlElements         XML elements list.
#
# Result:
#       If there's a delay elements in the given list then the result is a
#       number of seconds since epoch stored in the first one. Otherwise the
#       current time is returned.
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
                if {[regexp {(\d+)-(\d\d)-(\d\d)(T\d+:\d+:\d+)[^Z]*Z?} \
                            [::xmpp::xml::getAttr $attrs stamp] \
                            -> y m d t]} {
                    if {![catch {clock scan $y$m$d$t -gmt 1} seconds]} {
                        return $seconds
                    }
                }
            }
            jabber:x:delay {
                # 20060717T05:29:12
                # 20061118T03:35:56.415699
                if {[regexp {\d+\d\d\d\dT\d+:\d+:\d+} \
                            [::xmpp::xml::getAttr $attrs stamp] \
                            stamp]} {
                    if {![catch {clock scan $stamp -gmt 1} seconds]} {
                        return $seconds
                    }
                }
            }
        }
    }
    return [clock seconds]
}

# ::xmpp::delay::create --
#
#       Create delay element using XEP-0203 rules.
#
# Arguments:
#       seconds         (optional, defaults to the current time) Seconds since
#                       epoch to store in XML element.
#
# Results:
#       An XML element from XEP-0203 is created (without from attribute and
#       text cdata).
#
# Side effects:
#       None.

proc ::xmpp::delay::create {{seconds ""}} {
    if {[string equal $seconds ""]} {
        set seconds [clock seconds]
    }

    return [::xmpp::xml::create delay \
                -xmlns urn:xmpp:delay \
                -attrs [list stamp \
                             [clock format $seconds \
                                    -format %Y-%m-%dT%H:%M:%SZ \
                                    -gmt 1]]]
}

# ::xmpp::delay::createOld --
#
#       Create delay element using XEP-0091 (now deprecated) rules.
#
# Arguments:
#       seconds         (optional, defaults to the current time) Seconds since
#                       epoch to store in XML element.
#
# Results:
#       An XML element from XEP-0091 is created (without from attribute and
#       text cdata).
#
# Side effects:
#       None.

proc ::xmpp::delay::createOld {{seconds ""}} {
    if {[string equal $seconds ""]} {
        set seconds [clock seconds]
    }

    return [::xmpp::xml::create x \
                -xmlns jabber:x:delay \
                -attrs [list stamp \
                             [clock format $seconds \
                                    -format %Y%m%dT%H:%M:%S \
                                    -gmt 1]]]
}

# vim:ts=8:sw=4:sts=4:et