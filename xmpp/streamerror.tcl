# streamerror.tcl --
#
#       This file is part of the XMPP library. It provides routines for
#       parsing XMPP stream errors.
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::streamerror 0.1

namespace eval ::xmpp::streamerror {
    namespace export condition message error

    # Defined error conditions (see XMPP core, section 4.7.3)
    foreach {cond message} [list \
        bad-format               [::msgcat::mc "Bad Format"] \
        bad-namespace-prefix     [::msgcat::mc "Bad Namespace Prefix"] \
        conflict                 [::msgcat::mc "Conflict"] \
        connection-timeout       [::msgcat::mc "Connection Timeout"] \
        host-gone                [::msgcat::mc "Host Gone"] \
        host-unknown             [::msgcat::mc "Host Unknown"] \
        improper-addressing      [::msgcat::mc "Improper Addressing"] \
        internal-server-error    [::msgcat::mc "Internal Server Error"] \
        invalid-from             [::msgcat::mc "Invalid From"] \
        invalid-id               [::msgcat::mc "Invalid ID"] \
        invalid-namespace        [::msgcat::mc "Invalid Namespace"] \
        invalid-xml              [::msgcat::mc "Invalid XML"] \
        not-authorized           [::msgcat::mc "Not Authorized"] \
        policy-violation         [::msgcat::mc "Policy Violation"] \
        remote-connection-failed [::msgcat::mc "Remote Connection Failed"] \
        resource-constraint      [::msgcat::mc "Resource Constraint"] \
        restricted-xml           [::msgcat::mc "Restricted XML"] \
        see-other-host           [::msgcat::mc "See Other Host"] \
        system-shutdown          [::msgcat::mc "System Shutdown"] \
        undefined-condition      [::msgcat::mc "Undefined Condition"] \
        unsupported-encoding     [::msgcat::mc "Unsupported Encoding"] \
        unsupported-stanza-type  [::msgcat::mc "Unsupported Stanza Type"] \
        unsupported-version      [::msgcat::mc "Unsupported Version"] \
        xml-not-well-formed      [::msgcat::mc "XML Not Well-Formed"]] \
    {
        set StreamerrorDesc($cond) $message
    }
}

# ::xmpp::streamerror::condition --
#
#       Return XMPP stream error condition.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       Error condition.
#
# Side effects:
#       None.

proc ::xmpp::streamerror::condition {xmlElement} {
    return [lindex [ToList $xmlElement] 0]
}

# ::xmpp::streamerror::message --
#
#       Return XMPP stream error human-readable message.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       Error message.
#
# Side effects:
#       None.

proc ::xmpp::streamerror::message {xmlElement} {
    return [lindex [ToList $xmlElement] 1]
}

# ::xmpp::streamerror::ToList --
#
#       Convert XMPP stream error to a list of error condition and readable
#       message.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       A tuple {type, condition, message}.
#
# Side effects:
#       None.

proc ::xmpp::streamerror::ToList {xmlElement} {
    variable StreamerrorDesc

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels
    if {[llength $subels] == 0} {
        # Legacy error
        set cdata [string trim $cdata]
        if {[string length $cdata] > 0} {
            return [list legacy [::msgcat::mc "Stream Error (%s)" $cdata]]
        } else {
            return [list legacy [::msgcat::mc "Stream Error"]]
        }
    } else {
        # XMPP error
        set condition undefined-condition
        set desc ""
        set text ""
        foreach errelem $subels {
            ::xmpp::xml::split $errelem stag sxmlns sattrs scdata ssubels
            switch -- $stag {
                text {
                    if {[string equal $xmlns \
                                      urn:ietf:params:xml:ns:xmpp-streams]} {
                        set text $scdata
                    }
                }
                undefined-condition {
                    # TODO
                }
                default {
                    if {[info exists StreamerrorDesc($stag)]} {
                        set condition $stag
                        set desc $StreamerrorDesc($stag)
                    }
                }
            }
        }
        switch -glob -- [string length $desc]/[string length $text] {
            0/0 {
                return [list $condition [::msgcat::mc "Stream Error"]]
            }
            0/* {
                return [list $condition [::msgcat::mc "Stream Error: %s" \
                                                      $text]]
            }
            */0 {
                return [list $condition [::msgcat::mc "Stream Error (%s)" \
                                                      $desc]]
            }
            default {
                return [list $condition [::msgcat::mc "Stream Error (%s): %s" \
                                                      $desc $text]]
            }
        }
    }
}

# ::xmpp::streamerror::error --
#
#       Create XMPP stream error stanza.
#
# Arguments:
#       cond                        Error condition.
#       -text text                  Human readable description.
#
# Result:
#       Generated XMPP stream error XML element.
#
# Side effects:
#       None.

proc ::xmpp::streamerror::error {cond args} {
    set subels [list [::xmpp::xml::create $cond \
                              -xmlns urn:ietf:params:xml:ns:xmpp-streams]]

    foreach {key val} $args {
        switch -- $key {
            -text {
                lappend subels \
                        [::xmpp::xml::create text \
                                 -xmlns urn:ietf:params:xml:ns:xmpp-streams \
                                 -cdata $val]
            }
        }
    }

    return [::xmpp::xml::create error \
                    -xmlns http://etherx.jabber.org/streams \
                    -subelements $subels]
}

# vim:ts=8:sw=4:sts=4:et
