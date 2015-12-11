# hints.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Message Processing Hints (XEP-0334)
#
# Copyright (c) 2015 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.

package provide xmpp::hints 0.1

package require xmpp::xml 0.1

namespace eval ::xmpp::hints {}

# ::xmpp::hints::parse --
#
#       Find hint elements in a list and parse them.
#
# Arguments:
#       xmlElements         XML elements list.
#
# Result:
#       If there are any hints in the given list then the result is a
#       list of hints {store no-store no-permanent-store no-copy}.
#       Otherwise an empty list is returned.
#
# Side effects:
#       None.

proc ::xmpp::hints::parse {xmlElements} {
    set res {}

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels

        switch -- $xmlns {
            urn:xmpp:hints {
                lappend res $tag
            }
        }
    }

    return $res
}

# ::xmpp::hints::create --
#
#       Create a list of hint elements using XEP-0334 rules.
#
# Arguments:
#       hints       A list of desired hints. May contain values from the
#                   following list: {store no-store no-permanent-store no-copy}
#
# Results:
#       A list with XML elements from XEP-0334 is created.
#
# Side effects:
#       None.

proc ::xmpp::hints::create {hints} {
    set res {}

    foreach hint [lsort -unique $hints] {
        switch -- $hint {
            no-copy -
            no-store -
            no-permanent-store -
            store {
                lappend res [::xmpp::xml::create $hint -xmlns urn:xmpp:hints]
            }
            default {
                return -code error \
                       "Unknown message processing hint: \"$hint\""
            }
        }
    }

    return $res
}

# vim:ts=8:sw=4:sts=4:et
