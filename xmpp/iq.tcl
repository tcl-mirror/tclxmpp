# iq.tcl --
#
#       This file is part of the XMPP library. It implements the IQ processing
#       for high level applications. If you want to use low level parsing, use
#       -packetCommand option for ::xmpp::new.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::iq 0.1

namespace eval xmpp::iq {}

# ::xmpp::iq::registered --
#
#       Return all registered XML namespaces.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       A list of XMLNSs registered for the application.
#
# Side effects:
#       None.

proc ::xmpp::iq::registered {xlib} {
    variable SupportedNS

    set ns {}
    foreach idx [array names SupportedNS] {
        if {[string match $idx $xlib]} {
            set ns [concat $ns $SupportedNS($idx)]
        }
    }
    return [lsort -unique $ns]
}

# ::xmpp::iq::register --
#
#       Register IQ.
#
# Arguments:
#       type            IQ type to register. Must be either get or set. Types
#                       error and result cannot be registered.
#       tag             IQ XML tag pattern to register.
#       xmlns           XMLNS pattern to register.
#       cmd             Command to call when a registered IQ is received. This
#                       command must return one of the following: {error, ...},
#                       {result, ...}, ignore.
#
# Result:
#       Empty string or error if IQ type isn't get or set.
#
# Side effects:
#       An IQ is registered, and its XMLNS is added to a list of supported
#       namespaces.

proc ::xmpp::iq::register {type tag xmlns cmd} {
    RegisterIQ * $type $tag $xmlns $cmd
}

proc ::xmpp::iq::unregister {type tag xmlns} {
    UnregisterIQ * $type $tag $xmlns
}

# ::xmpp::iq::RegisterIQ --
#
#       Register IQ.
#
# Arguments:
#       xlib            XMPP token.
#       type            IQ type to register. Must be either get or set. Types
#                       error and result cannot be registered.
#       tag             IQ XML tag pattern to register.
#       xmlns           XMLNS pattern to register.
#       cmd             Command to call when a registered IQ is received. This
#                       command must return one of the following: {error, ...},
#                       {result, ...}, ignore.
#
# Result:
#       Empty string or error if IQ type isn't get or set.
#
# Side effects:
#       An IQ is registered, and its XMLNS is added to a list of supported
#       namespaces.

proc ::xmpp::iq::RegisterIQ {xlib type tag xmlns cmd} {
    variable IqCmd
    variable SupportedNS

    switch -- $type {
        get -
        set {}
        default {
            return -code error \
                   -errorinfo [::msgcat::mc "Illegal IQ type \"%s\"" $type]
        }
    }

    set IqCmd([list $xlib $type $tag $xmlns]) $cmd

    # TODO: Work with patterns
    if {[string equal $xmlns *]} return

    if {![info exists SupportedNS($xlib)]} {
        set SupportedNS($xlib) {}
    }
    set SupportedNS($xlib) \
        [lsort -unique [linsert $SupportedNS($xlib) 0 $xmlns]]
    return
}

proc ::xmpp::iq::UnregisterIQ {xlib type tag xmlns} {
    variable IqCmd
    variable SupportedNS

    if {![info exists IqCmd([list $xlib $type $tag $xmlns])]} {
        return
    }

    unset IqCmd([list $xlib $type $tag $xmlns])

    if {![info exists SupportedNS($xlib)]} return

    set idx [lsearch -exact $SupportedNS($xlib)]
    if {$idx >= 0} {
        set SupportedNS($xlib) [lreplace $SupportedNS($xlib) $idx $idx]
        if {[llength $SupportedNS($xlib)]} {
            unset SupportedNS($xlib)
        }
    }

    return
}

# ::xmpp::iq::process --
#
#       Process received IQ if it's registered. Otherwise reply with error.
#
# Arguments:
#       xlib            XMPP token.
#       from            JID from which the query is received.
#       type            Query type (get or set).
#       xmlElement      Query XML element.
#
# Result:
#       Empty string.
#
# Side effects:
#       A command corresponding to received IQ is called, and IQ reply is sent
#       back to a sending entity.

proc ::xmpp::iq::process {xlib from type xmlElement args} {
    variable IqCmd

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    if {[info exists IqCmd([list * $type $tag $xmlns])]} {
        set cmd $IqCmd([list * $type $tag $xmlns])
    } else {
        foreach idx [lsort [array names IqCmd]] {
            foreach {pxlib ptype ptag pxmlns} $idx break
        
            if {[string match $pxlib $xlib] && \
                    [string equal $ptype $type] && \
                    [string match $ptag $tag] && \
                    [string match $pxmlns $xmlns]} {
                set cmd $IqCmd($idx)
                break
            }
        }
    }

    if {[info exists IqCmd([list $xlib $type $tag $xmlns])]} {
        set cmd $IqCmd([list $xlib $type $tag $xmlns])
    } else {
        foreach idx [lsort [array names IqCmd]] {
            foreach {pxlib ptype ptag pxmlns} $idx break

            if {[string equal $pxlib $xlib] && \
                    [string equal $ptype $type] && \
                    [string match $ptag $tag] && \
                    [string match $pxmlns $xmlns]} {
                set cmd $IqCmd($idx)
                break
            }
        }
    }

    set id [::xmpp::xml::getAttr $args -id]

    if {![info exists cmd]} {
        ::xmpp::Debug 2 $xlib "unsupported $from $id $xmlns"
        ::xmpp::sendIQ $xlib error \
                       -query $xmlElement \
                       -error [::xmpp::stanzaerror::error \
                                       cancel service-unavailable] \
                       -to $from \
                       -id $id
    } else {
        set status [uplevel #0 $cmd [list $xlib $from $xmlElement] $args]

        switch -- [lindex $status 0] {
            result {
                ::xmpp::Debug 2 $xlib "result $from $id $xmlns"
                ::xmpp::sendIQ $xlib result \
                               -query [lindex $status 1] \
                               -to $from \
                               -id $id
            }
            error {
                ::xmpp::Debug 2 $xlib "error $from $id $xmlns"
                ::xmpp::sendIQ $xlib error \
                               -query $xmlElement \
                               -error [eval ::xmpp::stanzaerror::error \
                                                    [lrange $status 1 end]] \
                               -to $from \
                               -id $id
            }
            ignore {
                ::xmpp::Debug 2 $xlib "ignore $from $id $xmlns"
                # Do nothing, the request is supposed to be replied separately
            }
        }
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
