#!/usr/bin/env tclsh

# echo.tcl --
#
#       This file is an example provided with the XMPP library. It implements
#       a simple XMPP server-side component which returns every received packet
#       to sender. This component authenticates using XEP-0225 (Component
#       Connections) or XEP-0114 (Jabber Component Protocol).
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp
package require xmpp::sasl
package require xmpp::component

# ProcessPacket --
#
#       Swap from and to packet attribytes and send back the resulting packet.
#
# Arguments:
#       xlib            XMPP library instance.
#       xmlElement      XMPP packet.
#
# Result:
#       Empty string.
#
# Side effects:
#       An XMPP packet is sent.

proc ProcessPacket {xlib xmlElement} {
    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels nextCdata

    array set tmp $attrs

    if {![info exists tmp(from)] || ![info exists tmp(to)]} {
        return
    }

    set to        $tmp(to)
    set from      $tmp(from)
    set tmp(to)   $from
    set tmp(from) $to
    set attrs [array get tmp]
    
    set packet \
        [::xmpp::xml::merge $tag $xmlns $attrs $cdata $subels $nextCdata]

    ::xmpp::outXML $xlib $packet
    return
}

array set options [list -host   "" \
                        -port   5666 \
                        -server localhost \
                        -domain echo.localhost \
                        -secret secret \
                        -extra  "" \
                        -jcp    true]

if {[catch {
    if {([file exists [set file .echorc.tcl]]) \
            || ([file exists [set file ~/.echorc.tcl]])} {
        set args {}

        source $file

        array set at [list -permissions 600]
        array set at [file attributes $file]

        if {([set x [lsearch -exact $args "-secret"]] > 0) \
                    && (![expr $x%2]) \
                    && (![string match *00 $at(-permissions)])} {
            error "file should be mode 0600"
        }

        if {[llength $args] > 0} {
            array set options $args
        }
    }
} result]} {
    puts stderr "error in $file: $result"
}

array set options $argv

if {[string equal $options(-host) ""]} {
    set options(-host) $options(-server)
}

# Create an XMPP instance.
set xlib [::xmpp::new -packetCommand ProcessPacket]

# Connect to an XMPP server.
::xmpp::connect $xlib -host $options(-host) -port $options(-port)

if {!$options(-jcp)} {
    # XEP-0225

    # Open XMPP stream.
    set sessionID \
        [::xmpp::openStream $xlib $options(-server) -version 1.0]

    # Authenticate as a component (XEP-0225).
    ::xmpp::sasl::auth $xlib -domain $options(-domain) \
                             -secret $options(-secret)

    # Bind an extra domain name (XEP-0225).
    if {![string equal $options(-extra) ""]} {
        ::xmpp::sendIQ $xlib set \
                   -query [::xmpp::xml::create bind \
                                -xmlns urn:xmpp:component \
                                -subelement [::xmpp::xml::create hostname \
                                                    -cdata $options(-extra)]]
    }
} else {
    # XEP-0114

    # Open XMPP stream (XEP-0114).
    set sessionID \
        [::xmpp::openStream $xlib $options(-domain) \
                            -xmlns jabber:component:accept]

    # Authenticate as a component (XEP-0114).
    ::xmpp::component::auth $xlib -sessionID $sessionID \
                                  -secret $options(-secret)
}

# Enter event loop.
vwait forever

# vim:ts=8:sw=4:sts=4:et
