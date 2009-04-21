# pubsub.tcl --
#
#       This file is part of the XMPP library. It implements interface to
#       Publish-Subscribe Support (XEP-0060).
#
# Copyright (c) 2009 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package provide xmpp::pubsub 0.1

namespace eval ::xmpp::pubsub {
    variable ns
    array set ns [list \
        pubsub                     "http://jabber.org/protocol/pubsub" \
        owner                      "http://jabber.org/protocol/pubsub#owner" \
        collections                "http://jabber.org/protocol/pubsub#collections" \
        config-node                "http://jabber.org/protocol/pubsub#config-node" \
        create-and-configure       "http://jabber.org/protocol/pubsub#create-and-configure" \
        create-nodes               "http://jabber.org/protocol/pubsub#create-nodes" \
        delete-any                 "http://jabber.org/protocol/pubsub#delete-any" \
        delete-nodes               "http://jabber.org/protocol/pubsub#delete-nodes" \
        get-pending                "http://jabber.org/protocol/pubsub#get-pending" \
        instant-nodes              "http://jabber.org/protocol/pubsub#instant-nodes" \
        item-ids                   "http://jabber.org/protocol/pubsub#item-ids" \
        leased-subscription        "http://jabber.org/protocol/pubsub#leased-subscription" \
        meta-data                  "http://jabber.org/protocol/pubsub#meta-data" \
        manage-subscription        "http://jabber.org/protocol/pubsub#manage-subscription" \
        modify-affiliations        "http://jabber.org/protocol/pubsub#modify-affiliations" \
        multi-collection           "http://jabber.org/protocol/pubsub#multi-collection" \
        multi-subscribe            "http://jabber.org/protocol/pubsub#multi-subscribe" \
        outcast-affiliation        "http://jabber.org/protocol/pubsub#outcast-affiliation" \
        persistent-items           "http://jabber.org/protocol/pubsub#persistent-items" \
        presence-notifications     "http://jabber.org/protocol/pubsub#presence-notifications" \
        publish                    "http://jabber.org/protocol/pubsub#publish" \
        publisher-affiliation      "http://jabber.org/protocol/pubsub#publisher-affiliation" \
        purge-nodes                "http://jabber.org/protocol/pubsub#purge-nodes" \
        retract-items              "http://jabber.org/protocol/pubsub#retract-items" \
        retrieve-affiliations      "http://jabber.org/protocol/pubsub#retrieve-affiliations" \
        retrieve-default           "http://jabber.org/protocol/pubsub#retrieve-default" \
        retrieve-items             "http://jabber.org/protocol/pubsub#retrieve-items" \
        retrieve-subscriptions     "http://jabber.org/protocol/pubsub#retrieve-subscriptions" \
        subscribe                  "http://jabber.org/protocol/pubsub#subscribe" \
        subscription-options       "http://jabber.org/protocol/pubsub#subscription-options" \
        subscription-notifications "http://jabber.org/protocol/pubsub#subscription-notifications" \
        subscribe_authorization    "http://jabber.org/protocol/pubsub#subscribe_authorization" \
        subscribe_options          "http://jabber.org/protocol/pubsub#subscribe_options" \
        node_config                "http://jabber.org/protocol/pubsub#node_config" \
        event                      "http://jabber.org/protocol/pubsub#event"]
}

##########################################################################
#
# Entity use cases (5)
#

##########################################################################
#
# Discover features (5.1) is implemented in disco.tcl
# Discover nodes (5.2) is implemented in disco.tcl
# Discover node information (5.3) is implemented in disco.tcl
# Discover node meta-data (5.4) is implemented in disco.tcl
#

##########################################################################
#
# Discover items for a node (5.5) is NOT implemented in disco.tcl
# TODO
#

##########################################################################
#
# Retrieve subscriptions (5.6)
#
# Evaluates command for attribute lists
#

proc ::xmpp::pubsub::retrieveSubscriptions {xlib service args} {
    variable ns

    set attrs {}
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -node    { set attrs [list node $val] }
            -command { set commands [list $val] }
        }
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create subscriptions \
                                        -attrs $attrs]] \
        -to $service \
        -command [namespace code [list RetrieveSubscriptionsResult $commands]]
}

proc ::xmpp::pubsub::RetrieveSubscriptionsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set items {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            subscriptions {
                foreach item $ssubels {
                    ::xmpp::xml::split \
                            $item sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag subscription]} {
                        lappend items $ssattrs
                    }
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $items]
    }
}

##########################################################################
#
# Retrieve affiliations (5.6)
#
# Evaluates command for attribute lists
#

proc ::xmpp::pubsub::retrieveAffiliations {xlib service args} {
    variable ns

    set attrs {}
    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -node    { set attrs [list node $val] }
            -command { set commands [list $val] }
        }
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create affiliations \
                                        -attrs $attrs]] \
        -to $service \
        -command [namespace code [list RetrieveAffiliationsResult $commands]]
}

proc ::xmpp::pubsub::RetrieveAffiliationsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set items {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            affiliations {
                foreach item $ssubels {
                    ::xmpp::xml::split \
                            $item sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag affiliation]} {
                        lappend items $ssattrs
                    }
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $items]
    }
}

##########################################################################
#
# Subscriber use cases (6)
#

##########################################################################
#
# Subscribe to pubsub node "node" at service "service" (6.1)
#
# if node is empty then it's a subscription to root collection node (9.2)
#
# -jid "jid" is optional (when it's present it's included to sub request)
#
# -resource "res" is optional (when it's present bare_jid/res is included
# to sub request
#
# if both options are absent then user's bare JID is included to sub
# request
#
# Optional pubsub#subscribe_options parameters
# -deliver
# -digest
# -expire
# -include_body
# -show-values
# -subscription_type
# -subscription_depth
#

proc ::xmpp::pubsub::subscribe {xlib service node args} {
    variable ns

    set commands {}
    set options [form_type $ns(subscribe_options)]
    foreach {key val} $args {
        switch -- $key {
            -jid      { set jid $val }
            -resource { set resource $val }
            -command  { set commands [list $val] }
            -deliver            -
            -digest             -
            -expire             -
            -include_body       -
            -show-values        -
            -subscription_type  -
            -subscription_depth {
                set par [string range $opt 1 end]
                set options [concat $options [field pubsub#$par $val]]
            }
        }
    }

    if {![info exists jid]} {
        set jid [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]
    }

    if {[info exists resource]} {
        append jid /$resource
    }

    set attrs [list jid $jid]
    if {$node != ""} {
        lappend attrs node $node
    }

    if {[llength $options] > 2} {
        set options \
            [list [::xmpp::xml::create options \
                            -subelement [::xmpp::data::submitForm $options]]]
    } else {
        set options {}
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create subscribe \
                                         -attrs $attrs] \
                    -subelements $options] \
        -to $service \
        -command [namespace code [list SubscribeResult $commands]]
}

proc ::xmpp::pubsub::SubscribeResult {commands status xml} {
    variable ns

    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            subscription {
                # TODO: subscription-options
                if {[llength $commands] > 0} {
                    eval [lindex $commands 0] [list ok $sattrs]
                    return
                }
            }
        }
    }

    # Something strange: OK without subscription details
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok {}]
    }
}

##########################################################################
#
# Unsubscribe from pubsub node "node" at service "service" (6.2)
#
# if node is empty then it's a unsubscription from root collection node (9.2)
#
# -jid "jid" is optional (when it's present it's included to sub request)
#
# -resource "res" is optional (when it's present bare_jid/res is included
# to sub request
#
# if both options are absent then user's bare JID is included to sub
# request
#

proc ::xmpp::pubsub::unsubscribe {xlib service node args} {
    variable ns

    debugmsg pubsub [info level 0]

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -jid      { set jid $val }
            -subid    { set subid $val }
            -resource { set resource $val }
            -command  { set commands [list $val] }
        }
    }

    if {![info exists jid]} {
        set jid [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]
    }

    if {[info exists resource]} {
        append jid /$resource
    }

    set attrs [list jid $jid]
    if {$node != ""} {
        lappend attrs node $node
    }
    if {[info exists subid]} {
        lappend attrs subid $subid
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create unsubscribe \
                                        -attrs $attrs]] \
        -to $service \
        -command [namespace code [list UnsubscribeResult $commands]]
}

proc ::xmpp::pubsub::UnsubscribeResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Configure subscription options (6.3)
#

proc ::xmpp::pubsub::requestSubscriptionOptions {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -jid      { set jid $val }
            -subid    { set subid $val }
            -resource { set resource $val }
            -command  { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    if {![info exists jid]} {
        set jid [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]
    }

    if {[info exists resource]} {
        append jid /$resource
    }

    if {[info exists subid]} {
        set attrs [list node $node subid $subid jid $jid]
    } else {
        set attrs [list node $node jid $jid]
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create options \
                                        -attrs $attrs]] \
        -to $service \
        -command [namespace code [list SubscriptionOptionsResult $commands]]
}

proc ::xmpp::pubsub::SubscriptionOptionsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $tag {
            options {
                set form [::xmpp::data::findForm $ssubels]

                if {[llength $commands] > 0} {
                    eval [lindex $commands 0] \
                         [list ok [list $sattrs [lindex $form 0]]]
                    return
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok {}]
    }
}

proc ::xmpp::pubsub::sendSubscriptionOptions {xlib service node restags args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -jid      { set jid $val }
            -subid    { set subid $val }
            -resource { set resource $val }
            -command  { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    if {![info exists jid]} {
        set jid [::xmpp::jid::stripResource [::xmpp::Set $xlib jid]]
    }

    if {[info exists resource]} {
        append jid /$resource
    }

    if {[info exists subid]} {
        set attrs [list node $node subid $subid jid $jid]
    } else {
        set attrs [list node $node jid $jid]
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                           -xmlns $ns(pubsub) \
                           -subelement [::xmpp::xml::create options \
                                            -attrs $attrs \
                                            -subelements $restags]] \
        -to $service \
        -command [namespace code [list SendSubscriptionOptionsResult $commands]]
}

proc ::xmpp::pubsub::SendSubscriptionOptionsResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Retrieve items for a node (6.4)
# Node must not be empty
# Evaluates command with list of items
#
# -max_items $number (request $number last items)
# -items $item_id_list (request specific items)

proc ::xmpp::pubsub::retrieveItems {xlib service node args} {
    variable ns

    set commands {}
    set items {}
    foreach {key val} $args {
        switch -- $key {
            -command   { set commands [list $val] }
            -subid     { set subid $val }
            -max_items { set max_items $val }
            -items {
                foreach id $val {
                    lappend items [::xmpp::xml::create item
                                       -attrs [list id $id]]
                }
            }
        }
    }

    if {$node == ""} {
        return -code error "Node must not be empty"
    }

    if {[info exists subid]} {
        set attrs [list node $node subid $subid]
    } else {
        set attrs [list node $node]
    }

    if {[info exists max_items]} {
        lappend attrs max_items $max_items
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create items \
                                    -attrs $attrs \
                                    -subelements $items]] \
        -to $service \
        -command [namespace code [GetItemsResult $commands]]
}

proc ::xmpp::pubsub::GetItemsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0 ][list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    set items {}
    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns attrs scdata ssubels

        switch -- $stag {
            items {
                foreach item $ssubels {
                    ::xmpp::xml::split \
                            $item sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag item]} {
                        lappend items $item
                    }
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $items]
    }
}

##########################################################################
#
# Publisher use cases (7)
#

##########################################################################
#
# Publish item "itemid" to pubsub node "node" at service "service" (7.1)
# payload is a LIST of xml tags
# node must not be empty

proc ::xmpp::pubsub::publishItem {xlib service node itemid args} {
    variable ns

    debugmsg pubsub [info level 0]

    set commands {}
    set payload {}
    set transient 0
    foreach {key val} $args {
        switch -- $key {
            -transient { set transient $val }
            -payload   { set payload $val }
            -command   { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    if {[string equal $itemid ""]} {
        set attrs {}
    } else {
        set attrs [list id $itemid]
    }

    if {$transient} {
        set item {}
    } else {
        set item [list [::xmpp::xml::create item \
                            -attrs $attrs \
                            -subelements $payload]]
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create publish \
                                        -attrs [list node $node] \
                                        -subelements $item]] \
        -to $service \
        -command [namespace code [list PublishItemResult $commands]]
}

proc ::xmpp::pubsub::PublishItemResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Delete item "itemid" from pubsub node "node" at service "service" (7.2)
# node and itemid must not be empty
# -notify is a boolean (true, false, 1, 0)

proc ::xmpp::pubsub::deleteItem {xlib service node itemid args} {
    variable ns

    set commands {}
    set notify 0
    foreach {key val} $args {
        switch -- $key {
            -notify  { set notify $val }
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    if {[string equal $itemid ""]} {
        return -code error "Item ID must not be empty"
    }

    set attrs [list node $node]
    if {[string is true -strict $notify]} {
        lappend attrs notify true
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create retract \
                                    -attrs $attrs \
                                    -subelement [::xmpp::xml::create item \
                                                  -attrs [list id $itemid]]]] \
        -to $service \
        -command [namespace code [list DeleteItemResult $commands]]
}

proc ::xmpp::pubsub::DeleteItemResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Owner use cases (8)
#

##########################################################################
#
# Create pubsub node "node" at service "service" (8.1)
#
# 8.1.2 create_node xlib service node -command callback
# or    create_node xlib service node -access_model model -command callback
#
# 8.1.3 create_node xlib service node -command callback \
#                                 -title title \
#                                  ........... \
#                                 -body_xslt xslt
#
# Optional pubsub#node_config parameters
# -access_model
# -body_xslt
# -collection
# -dataform_xslt
# -deliver_notifications
# -deliver_payloads
# -itemreply
# -children_association_policy
# -children_association_whitelist
# -children
# -children_max
# -max_items
# -max_payload_size
# -node_type
# -notify_config
# -notify_delete
# -notify_retract
# -persist_items
# -presence_based_delivery
# -publish_model
# -replyroom
# -replyto
# -roster_groups_allowed
# -send_last_published_item
# -subscribe
# -title
# -type

proc ::xmpp::pubsub::createNode {xlib service node args} {
    variable ns

    debugmsg pubsub [info level 0]

    set commands {}
    set options {}
    set fields [form_type $ns(node_config)]
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
            -access_model                   -
            -body_xslt                      -
            -collection                     -
            -dataform_xslt                  -
            -deliver_notifications          -
            -deliver_payloads               -
            -itemreply                      -
            -children_association_policy    -
            -children_association_whitelist -
            -children                       -
            -children_max                   -
            -max_items                      -
            -max_payload_size               -
            -node_type                      -
            -notify_config                  -
            -notify_delete                  -
            -notify_retract                 -
            -persist_items                  -
            -presence_based_delivery        -
            -publish_model                  -
            -replyroom                      -
            -replyto                        -
            -roster_groups_allowed          -
            -send_last_published_item       -
            -subscribe                      -
            -title                          -
            -type                           {
                set par [string range $opt 1 end]
                set fields [concat $fields [field pubsub#$par $val]]
            }
        }
    }

    if {[string equal $node ""]} {
        set attrs {}
    } else {
        set attrs [list node $node]
    }

    if {[llength $fields] > 2} {
        set fields [list [::xmpp::data::submitForm $fields]]
    } else {
        set fields {}
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(pubsub) \
                    -subelement [::xmpp::xml::create create \
                                        -attrs $attrs] \
                    -subelement [::xmpp::xml::create configure \
                                        -subelements $fields]] \
        -to $service \
        -command [namespace code [list CreateNodeResult $node $commands]]
}

proc ::xmpp::pubsub::form_type {value} {
    return [list FORM_TYPE [list $value]]
}

proc ::xmpp::pubsub::field {var value} {
    return [list $var [list $value]]
}

proc ::xmpp::pubsub::CreateNodeResult {node commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    if {[string equal $node ""]} {
        # Instant node: get node name from the answer

        ::xmpp::xml::split $xml tag xmlns attrs cdata subels

        foreach subel $subels {
            ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
            if {[string equal $stag create]} {
                set node [::xmpp::xml::getAttr $sattrs node]
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $node]
    }
}

##########################################################################
#
# Configure pubsub node "node" at service "service" (8.2)
# node must not be empty
#

proc ::xmpp::pubsub::configureNode {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create configure \
                                        -attrs [list node $node]]] \
        -to $service \
        -command [namespace code [list ConfigureNodeResult $commands]]
}

proc ::xmpp::pubsub::ConfigureNodeResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            configure {
                set node [::xmpp::xml::getAttr $sattrs node]
                set form [::xmpp::data::findForm $ssubels]

                if {[llength $commands] > 0} {
                    eval [lindex $commands 0] \
                         [list ok [list $node [lindex $form 0]]]
                    return
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok {}]
    }
}

proc ::xmpp::pubsub::sendConfigureNode {xlib service node restags args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                           -xmlns $ns(owner) \
                           -subelement [::xmpp::xml::create configure \
                                            -attrs [list node $node] \
                                            -subelements $restags]] \
        -to $service \
        -command [namespace code [list SendConfigureNodeResult $commands]]
}

proc ::xmpp::pubsub::SendConfigureNodeResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Request default configuration options (8.3)
#

proc ::xmpp::pubsub::requestDefaultConfig {xlib service args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create default]] \
        -to $service \
        -command [namespace code [list RequestDefaultConfigResult $commands]]
}

proc ::xmpp::pubsub::RequestDefaultConfigResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            default {
                set form [::xmpp::data::findForm $ssubels]

                if {[llength $commands] > 0} {
                    eval [lindex $commands 0] \
                         [list ok [lindex $form 0]]
                    return
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok {}]
    }
}

##########################################################################
#
# Delete a node (8.4)
# node must not be empty
#

proc ::xmpp::pubsub::deleteNode {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create delete \
                                    -attrs [list node $node]]] \
        -to $service \
        -command [namespace code [list DeleteNodeResult $commands]]
}

proc ::xmpp::pubsub::DeleteNodeResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Purge all node items (8.5)
# node must not be empty
#

proc ::xmpp::pubsub::purgeItems {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create purge \
                                    -attrs [list node $node]]] \
        -to $service \
        -command [namespace code [list PurgeItemsResult $commands]]
}

proc ::xmpp::pubsub::PurgeItemsResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Manage subscription requests (8.6)
# is done in messages.tcl
#

##########################################################################
#
# Request all pending subscription requests (8.6.1)
# TODO

#proc ::xmpp::pubsub::requestPendingSubscription {xlib service} {
#    variable ns
#
#    # Let xcommands.tcl do the job
#    xcommands::execute $xlib $service $ns(get-pending)
#}

##########################################################################
#
# Manage subscriptions (8.7)
#
# Callback is called with list of entities:
# {jid JID subscription SUB subid ID}
#

proc ::xmpp::pubsub::requestSubscriptions {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create subscriptions \
                                    -attrs [list node $node]]] \
        -to $service \
        -command [namespace code [list RequestSubscriptionsResult $commands]]
}

proc ::xmpp::pubsub::RequestSubscriptionsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set entities {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            subscriptions {
                foreach entity $ssubels {
                    ::xmpp::xml::split \
                            $entity sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag subscription]} {
                        lappend entities $ssattrs
                    }
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $entities]
    }
}

##########################################################################

proc ::xmpp::pubsub::modifySubscriptions {xlib service node entities args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    set subscriptions {}
    foreach entity $entities {
        lappend subscriptions [::xmpp::xml::create subscription \
                                        -attrs $entity]
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create subscriptions \
                                        -attrs [list node $node] \
                                        -subelements $subscriptions]] \
        -to $service \
        -command [namespace code [list ModifySubscriptionsResult $commands]]
}

proc ::xmpp::pubsub::ModifySubscriptionsResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Retrieve current affiliations (8.8)
# Evaluates command with list of entity attributes lists
#

proc ::xmpp::pubsub::requestAffiliations {xlib service node args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    ::xmpp::sendIQ $xlib get \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create affiliations]] \
        -to $service \
        -command [namespace code [list RequestAffiliationsResult $commands]]
}

proc ::xmpp::pubsub::RequestAffiliationsResult {commands status xml} {
    if {![string equal $status ok]} {
        if {[llength $commands] > 0} {
            eval [lindex $commands 0] [list $status $xml]
        }
        return
    }

    set entities {}

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            affiliations {
                foreach entity $ssubels {
                    ::xmpp::xml::split \
                            $entity sstag ssxmlns sattrs sscdata sssubels

                    if {[string equal $sstag affiliation]} {
                        lappend entities $ssattrs
                    }
                }
            }
        }
    }

    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list ok $entites]
    }
}

##########################################################################

proc ::xmpp::pubsub::modifyAffiliations {xlib service node entities args} {
    variable ns

    set commands {}
    foreach {key val} $args {
        switch -- $key {
            -command { set commands [list $val] }
        }
    }

    if {[string equal $node ""]} {
        return -code error "Node must not be empty"
    }

    set affiliations {}
    foreach entity $entities {
        lappend affiliations [::xmpp::xml::create affiliation \
                                        -attrs $entity]
    }

    ::xmpp::sendIQ $xlib set \
        -query [::xmpp::xml::create pubsub \
                    -xmlns $ns(owner) \
                    -subelement [::xmpp::xml::create affiliations \
                                        -attrs [list node $node] \
                                        -subelements $affiliations]] \
        -to $service \
        -command [namespace code [list ModifyAffiliationsResult $commands]]
}

proc ::xmpp::pubsub::ModifyAffiliationsResult {commands status xml} {
    if {[llength $commands] > 0} {
        eval [lindex $commands 0] [list $status $xml]
    }
}

##########################################################################
#
# Collection nodes (9)
#

##########################################################################
#
# Subscribe to a collection node (9.1)
# Implemented in
# pubsub::subscribe xlib service node id \
#                    -subscription_type {nodes|items} \
#                    -subscription_depth {1|all}
#

##########################################################################
#
# Root collection node (9.2)
# Implemented in pubsub::subscribe and pubsub::unsubscribe with empty node
#

##########################################################################
#
# Create collection node (9.3)
# Implemented in
# pubsub::create_node xlib service node \
#                      -node_type collection
#

##########################################################################
#
# Create a node associated with a collection (9.4)
# Implemented in
# pubsub::create_node xlib service node \
#                      -collection collection
#

##########################################################################
#
# Associate an existing node with a collection (9.5)
# Implemented in TODO

##########################################################################
#
# Diassociate an node from a collection (9.6)
# Implemented in TODO

# vim:ts=8:sw=4:sts=4:et
