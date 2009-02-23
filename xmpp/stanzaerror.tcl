# stanzaerror.tcl --
#
#       This file is part of the XMPP library. It provides routines for
#       parsing and generating XMPP stanza errors. For legacy errors XEP-0086
#       rules are used.
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::stanzaerror 0.1

namespace eval ::xmpp::stanzaerror {
    namespace export registerType registerError type condition message error

    # Defined error types (see XMPP core, section 9.3.2)
    array set Type [list \
        cancel   [::msgcat::mc "Unrecoverable Error"] \
        continue [::msgcat::mc "Warning"] \
        modify   [::msgcat::mc "Request Error"] \
        auth     [::msgcat::mc "Authentication Error"] \
        wait     [::msgcat::mc "Temporary Error"]]

    set DefinedConditions {}

    # Defined error conditions (see XMPP core, section 9.3.3, and XEP-0086).
    foreach {clist lcode type cond description} [list \
        {400} 400 modify bad-request             [::msgcat::mc "Bad Request"] \
        {409} 409 cancel conflict                [::msgcat::mc "Conflict"] \
        {501} 501 cancel feature-not-implemented [::msgcat::mc "Feature Not\
                                                                Implemented"] \
        {403} 403 auth   forbidden               [::msgcat::mc "Forbidden"] \
        {302} 302 modify gone                    [::msgcat::mc "Gone"] \
        {500} 500 wait   internal-server-error   [::msgcat::mc "Internal Server\
                                                                Error"] \
        {404} 404 cancel item-not-found          [::msgcat::mc "Item Not\
                                                                Found"] \
        {}    400 modify jid-malformed           [::msgcat::mc "JID\
                                                                Malformed"] \
        {406} 406 modify not-acceptable          [::msgcat::mc "Not\
                                                                Acceptable"] \
        {405} 405 cancel not-allowed             [::msgcat::mc "Not Allowed"] \
        {401} 401 auth   not-authorized          [::msgcat::mc "Not\
                                                                Authorized"] \
        {402} 402 auth   payment-required        [::msgcat::mc "Payment\
                                                                Required"] \
        {}    404 wait   recipient-unavailable   [::msgcat::mc "Recipient\
                                                                Unavailable"] \
        {}    302 modify redirect                [::msgcat::mc "Redirect"] \
        {407} 407 auth   registration-required   [::msgcat::mc "Registration\
                                                                Required"] \
        {}    404 cancel remote-server-not-found [::msgcat::mc "Remote Server\
                                                                Not Found"] \
        {408 504} \
              504 wait   remote-server-timeout   [::msgcat::mc "Remote Server\
                                                                Timeout"] \
        {}    500 wait   resource-constraint     [::msgcat::mc "Resource\
                                                                Constraint"] \
        {502 503 510} \
              503 cancel service-unavailable     [::msgcat::mc "Service\
                                                                Unavailable"] \
        {}    407 auth   subscription-required   [::msgcat::mc "Subscription\
                                                                Required"] \
        {}    500 any    undefined-condition     [::msgcat::mc "Undefined\
                                                                Condition"] \
        {}    400 wait   unexpected-request      [::msgcat::mc "Unexpected\
                                                                Request"]] \
    {
        lappend DefinedConditions $cond
        set Description($type,$cond) $description
        # XEP-0086
        foreach code $clist {
            set TypeDescelem($code) [list $type $cond]
        }
        set LegacyCodes($cond) $lcode
    }

    # Error messages from jabberd14
    # [::msgcat::mc "Access Error"]
    # [::msgcat::mc "Address Error"]
    # [::msgcat::mc "Application Error"]
    # [::msgcat::mc "Format Error"]
    # [::msgcat::mc "Not Found"]
    # [::msgcat::mc "Not Implemented"]
    # [::msgcat::mc "Recipient Error"]
    # [::msgcat::mc "Remote Server Error"]
    # [::msgcat::mc "Request Timeout"]
    # [::msgcat::mc "Server Error"]
    # [::msgcat::mc "Unauthorized"]
    # [::msgcat::mc "Username Not Available"]
}

# ::xmpp::stanzaerror::registerType --
#
#       Register additional stanza error type (e.g. for SASL errors).
#
# Arguments:
#       type            Error type.
#       description     Error type human-readable description.
#
# Result:
#       Empty string.
#
# Side effects:
#       A new error type and description are stored.

proc ::xmpp::stanzaerror::registerType {type description} {
    variable Type

    set Type($type) $description
    return
}

# ::xmpp::stanzaerror::registerError --
#
#       Register additional stanza error (pair type-condition).
#
# Arguments:
#       lcode           Legacy code for the error. If zero then [error] will
#                       not add the code to error stanza.
#       type            Error type.
#       cond            Error condition.
#       description     Error human-readable description.
#
# Result:
#       Empty string.
#
# Side effects:
#       A new error type, condition and description are stored. Also, a legacy
#       error code is assigned to the specified error.

proc ::xmpp::stanzaerror::registerError {lcode type cond description} {
    variable DefinedConditions
    variable Description

    lappend DefinedConditions $cond
    set Description($type,$cond) $description
    set LegacyCodes($cond) $lcode
    return
}

# ::xmpp::stanzaerror::type --
#
#       Return XMPP stanza error type.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       Error type.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::type {xmlElement} {
    return [lindex [ToList $xmlElement] 0]
}

# ::xmpp::stanzaerror::condition --
#
#       Return XMPP stanza error condition.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       Error condition.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::condition {xmlElement} {
    return [lindex [ToList $xmlElement] 1]
}

# ::xmpp::stanzaerror::message --
#
#       Return XMPP stanza error human-readable message.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       Error message.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::message {xmlElement} {
    return [lindex [ToList $xmlElement] 2]
}

# ::xmpp::stanzaerror::ToList --
#
#       Convert XMPP stanza error to a list of error type, condition and
#       readable message.
#
# Arguments:
#       xmlElement      Stanza error XML element.
#
# Result:
#       A tuple {type, condition, message}.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::ToList {xmlElement} {
    variable Type
    variable DefinedConditions
    variable Description
    variable TypeDescelem

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[::xmpp::xml::isAttr $attrs type]} {
        # XMPP error

        set type [::xmpp::xml::getAttr $attrs type]
        set cond undefined-condition
        set description ""
        set textdescription ""

        foreach subel $subels {
            ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
            switch -- $stag {
                text {
                    if {[string equal $sxmlns \
                                      urn:ietf:params:xml:ns:xmpp-stanzas]} {
                        set textdescription ": $scdata"
                    }
                }
                undefined-condition {
                    # TODO
                    set description $Description(any,undefined-condition)
                }
                default {
                    if {[lsearch -exact $DefinedConditions $stag] >= 0} {
                        set cond $stag
                        if {[info exists Description($type,$stag)] && \
                                [string equal $description ""]} {
                            set description $Description($type,$stag)
                        }
                    } else {
                        # TODO
                    }
                }
            }
        }
        if {[info exists Type($type)]} {
            set typedesc $Type($type)
        }
        set res ""
        if {![string equal $description ""]} {
            set res $description
        }
        if {[info exists typedesc] && ![string equal $typedesc ""]} {
            if {[string equal $res ""]} {
                set res $typedesc
            } else {
                set res "$typedesc ($res)"
            }
        }
        return [list $type $cond "$res$textdescription"]
    } elseif {[::xmpp::xml::isAttr $attrs code]} {
        # Legacy error. Description is in $cdata

        set code [::xmpp::xml::isAttr $attrs code]
        if {[string is integer $code]} {
            if {[info exists TypeDescelem($code)]} {
                set type [lindex $TypeDescelem($code) 0]
                set desc [lindex $TypeDescelem($code) 1]
            } else {
                set type none
                set desc none
            }
            return [list $type $desc "$code ([::msgcat::mc $cdata])"]
        } else {
            return [list none none [::msgcat::mc $cdata]]
        }
    } else {
        return [list none none [::msgcat::mc $cdata]]
    }
}

# ::xmpp::stanzaerror::error --
#
#       Create error stanza.
#
# Arguments:
#       type                        Error type.
#       cond                        Error condition.
#       -old boolean                Create legacy error if true.
#       -text text                  Human readable description.
#       -application-specific xml   Application-specific error condition.
#
# Result:
#       Generated error XML element.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::error {type cond args} {
    set old false
    foreach {key val} $args {
        switch -- $key {
            -old {
                set old $val
            }
        }
    }
    if {$old} {
        return [eval [list LegacyError $type $cond] $args]
    } else {
        return [eval [list XMPPError $type $cond] $args]
    }
}

# ::xmpp::stanzaerror::LegacyError --
#
#       Create legacy (pre-XMPP) error stanza.
#
# Arguments:
#       type                        Error type.
#       cond                        Error condition.
#       -text text                  Human readable description.
#
# Result:
#       Generated pre-XMPP error XML element which corresponds to specified
#       XMPP error type and condition.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::LegacyError {type cond args} {
    variable LegacyCodes
    variable Description

    if {[info exists LegacyCodes($cond)] && $LegacyCodes($cond) > 0} {
        set code $LegacyCodes($cond)
    } else {
        set code 503
    }

    if {[info exists Description($type,$cond)]} {
        set description $Description($type,$cond)
    } else {
        set description ""
    }

    foreach {opt val} $args {
        switch -- $opt {
            -text {
                set description $val
            }
        }
    }

    return [::xmpp::xml::create error -attrs [list code $code] \
                                      -cdata $description]
}

# ::xmpp::stanzaerror::XMPPError --
#
#       Create XMPP error stanza.
#
# Arguments:
#       type                        Error type.
#       cond                        Error condition.
#       -text text                  Human readable description.
#       -application-specific xml   Application-specific error condition.
#
# Result:
#       Generated XMPP error XML element.
#
# Side effects:
#       None.

proc ::xmpp::stanzaerror::XMPPError {type cond args} {
    variable LegacyCodes

    set subels [list [::xmpp::xml::create $cond \
                              -xmlns urn:ietf:params:xml:ns:xmpp-stanzas]]

    foreach {key val} $args {
        switch -- $key {
            -text {
                lappend subels \
                        [::xmpp::xml::create text \
                                 -xmlns urn:ietf:params:xml:ns:xmpp-stanzas \
                                 -cdata $val]
            }
            -application-specific {
                lappend subels $val
            }
        }
    }

    set attrs [list type $type]
    if {[info exists LegacyCodes($cond)] && $LegacyCodes($cond) > 0} {
        lappend attrs code $LegacyCodes($cond)
    }

    return [::xmpp::xml::create error -attrs $attrs -subelements $subels]
}

# vim:ts=8:sw=4:sts=4:et
