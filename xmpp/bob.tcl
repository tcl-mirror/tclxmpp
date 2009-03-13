# bob.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Bits of Binary (XEP-0231)
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require base64

package provide xmpp::bob 0.1

namespace eval ::xmpp::bob {
    variable cache
    array set cache {}
}

# ::xmpp::bob::clear --
#
#       Clear bits-of-binary cache element (or the whole cache).
#
# Arguments:
#       cid             (optional) CID of data to delete from cache.
#
# Result:
#       Empty string.
#
# Side effects:
#       The element is deleted from cache of bits or the cache is emptied.

proc ::xmpp::bob::clear {{cid *}} {
    variable cache

    array unset cache $cid
    return
}

# ::xmpp::bob::cache --
#
#       Find bob element in a list and cache it.
#
# Arguments:
#       xmlElements         XML elements list.
#
# Result:
#       Empty string.
#
# Side effects:
#       If there are bits-of-binary elements in XML elements then they
#       are stored in the cache and are scheduled for removal.

proc ::xmpp::bob::cache {xmlElements} {
    variable cache

    foreach element $xmlElements {
        ::xmpp::xml::split $element tag xmlns attrs cdata subels

        switch -- $xmlns {
            urn:xmpp:bob {
                set cid [::xmpp::xml::getAttr $attrs cid]
                set type [::xmpp::xml::getAttr $attrs type]
                if {[string equal $cid ""] || [string equal $type ""]} {
                    return
                }
                set maxAge [::xmpp::xml::getAttr $attrs max-age -1]
                set data [base64::decode $cdata]
                if {![regexp {(.*)\+(.*)@bob\.xmpp\.org} $cid -> \
                             algo hash]} {
                    return
                }
                switch -- $algo {
                    sha1 {
                        if {![string equal [sha1::sha1 $data] $hash]} {
                            return
                        }
                    }
                    default {
                        return
                    }
                }
                set cache($cid) [list $type $data]
                if {$maxAge >= 0} {
                    after [expr {$maxAge * 1000}] \
                          [namespace code [list clear $cid]]
                }
            }
        }
    }
    return
}

proc ::xmpp::bob::get {cid} {
    variable cache

    if {[info exists cache($cid)]} {
        return $cache($cid)
    } else {
        return {}
    }
}

# ::xmpp::bob::request --
#
#       Request bits-of-binary element.
#
# Arguments:
#       xlib            XMPP token.
#       jid             JID to request BOB data.
#       cid             CID of data.
#
# Result:
#
# Side effects:
#       None.

proc ::xmpp::bob::request {xlib jid cid args} {
    variable cache

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

    if {[info exists cache($cid)]} {
        if {[llength $commands] > 0} {
            after idle \
                  [list uplevel #0 [lindex $commands 0] [list ok $cache($cid)]]
            return
        } else {
            return $cache($cid)
        }
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create data \
                        -xmlns urn:xmpp:bob \
                        -attrs [list cid $cid]] \
        -to $jid \
        -command [namespace code [list ParseAnswer $xlib $jid $cid $commands]]
    return
}

proc ::xmpp::bob::ParseAnswer {xlib jid cid commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list $status $xml]
        }
        return
    }

    cache [list $xml]

    if {[info exists cache($cid)]} {
        if {[llength $commands] > 0} {
            uplevel #0 [lindex $commands 0] [list ok $cache($cid)]]
        }
    }
}

proc ::xmpp::bob::cid {data} {
    return sha1+[sha1::sha1 $data]@bob.xmpp.org
}

proc ::xmpp::bob::data {type data args} {
    set maxAge -1
    foreach {key val} $args {
        switch -- $key {
            -maxage {
                set maxAge $val
            }
            default {
                return -code error \
                       -errorcode [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set attrs [list cid [cid $data] \
                    type $type]
    if {$maxAge >= 0} {
        lappend attrs max-age $maxAge
    }

    return [::xmpp::xml::create data -xmlns urn:xmpp:bob \
                                     -attrs $attrs \
                                     -cdata [base64::encode $data]]
}

# vim:ts=8:sw=4:sts=4:et
