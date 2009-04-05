# pep.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Personal Eventing Protocol (XEP-0163).
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::pubsub

package provide xmpp::pep 0.1

namespace eval ::xmpp::pep {}

#
#
# PEP Creating a node (5)
# -access_model (open, presence (default), roster, whitelist)
# -roster_groups_allowed (roster group list if access is roster)

proc ::xmpp::pep::createNode {xlib node args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    set service [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]

    eval [list ::xmpp::pubsub::createNode $xlib $service $node] $args
}

# PEP Deleting a node

proc ::xmpp::pep::deleteNode {xlib node args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    set service [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]

    eval [list ::xmpp::pubsub::deleteNode $xlib $service $node] $args
}

#
#
# Publish item to PEP node "node" (8)
# payload is a list of xml tags
# node must not be empty
# itemid may be empty

proc ::xmpp::pep::publishItem {xlib node itemid args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    set service [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]

    eval [list ::xmpp::pubsub::publishItem $xlib $service $node $itemid] $args
}

#
#
# Delete item from PEP node "node"
# node must not be empty
# itemid must not be empty

proc ::xmpp::pep::deleteItem {xlib node itemid args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    if {[string equal $itemid ""]} {
        return -code error "Item ID must not be empty"
    }

    set service [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]

    eval [list ::xmpp::pubsub::deleteItem $xlib $service $node $itemid] $args
}

#
#
# Subscribe to PEP node "node" at bare JID "to" (5.2)
# node must not be empty
#
# -jid "jid" is optional (when it's present it's included to sub request)
#
# -resource "res" is optional (when it's present bare_jid/res is included
# to sub request
#
# if both options are absent then user's bare JID is included to sub
# request

proc ::xmpp::pep::subscribe {xlib to node args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    eval [list ::xmpp::pubsub::subscribe $xlib $to $node] $args
}

#
#
# Unsubscribe from PEP node "node" at bare JID "to" (undocumented?!)
# node must not be empty
#
# -jid "jid" is optional (when it's present it's included to sub request)
#
# -resource "res" is optional (when it's present bare_jid/res is included
# to sub request
#
# if both options are absent then user's bare JID is included to sub
# request

proc ::xmpp::pep::unsubscribe {xlib to node args} {
    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    eval [list ::xmpp::pubsub::unsubscribe $xlib $to $node] $args
}

# vim:ts=8:sw=4:sts=4:et
