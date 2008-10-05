# xmpp.tcl --
#
#       This file is part of the XMPP library. It implements the main library
#       routines.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require msgcat
package require xmpp::jid
package require xmpp::xml
package require xmpp::transport::tcp
package require xmpp::streamerror
package require xmpp::stanzaerror
package require xmpp::iq

package provide xmpp 0.1

namespace eval ::xmpp {
    variable debug 0
} 

######################################################################

proc ::xmpp::client {xlib command args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$command"

    set cmd -${command}Command

    if {[info exists state($cmd)]} {
        uplevel #0 $state($cmd) [list $xlib] $args
    }
    return
}

######################################################################

proc ::xmpp::new {args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    if {[llength $args] > 0 && ![string match -* [lindex $args 0]]} {
        set xlib [lindex $args 0]
        set args [lrange $args 1 end]

        if {[info exists $xlib]} {
            return -code error \
                   -errorinfo [::msgcat::mc "An existing variable \"%s\"\
                                             cannot be used as an XMPP\
                                             token" $xlib]
        }
    } else {
        set xlib [namespace current]::[incr id]

        # Variable id always grows but user may occupy some values

        while {[info exists $xlib]} {
            set xlib [namespace current]::[incr id]
        }
    }

    foreach {key val} $args {
        switch -- $key {
            -packetCommand -
            -messageCommand -
            -presenceCommand -
            -reconnectCommand -
            -disconnectCommand -
            -statusCommand -
            -errorMsgCommand {set attrs($key) $val}
        }
    }

    variable $xlib
    upvar 0 $xlib state

    array unset state
    set state(status) disconnected

    # A sequence of IQ ids
    set state(id) 0

    array set state [array get attrs]

    if {[info exists state(-messageCommand)]} {
        RegisterElement $xlib message * \
                        [namespace code [list ParseMessage $xlib]]
    }
    if {[info exists state(-presenceCommand)]} {
        RegisterElement $xlib presence * \
                        [namespace code [list ParsePresence $xlib]]
    }
    if {![info exists state(-packetCommand)]} {
        RegisterElement $xlib iq * \
                        [namespace code [list ParseIQ $xlib]]
    }

    RegisterElement $xlib error http://etherx.jabber.org/streams \
                    [namespace code [list ParseStreamError $xlib]]
    RegisterElement $xlib features http://etherx.jabber.org/streams \
                    [namespace code [list ParseStreamFeatures $xlib]]

    Debug 2 $xlib ""

    return $xlib
}

proc ::xmpp::free {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    if {![status $xlib disconnected]} {
        return -code error -errorinfo [::msgcat::mc "Free without disconnect"]
    }

    if {[info exists state(-messageCommand)]} {
        UnregisterElement $xlib message *
    }
    if {[info exists state(-presenceCommand)]} {
        UnregisterElement $xlib presence *
    }
    if {![info exists state(-packetCommand)]} {
        UnregisterElement $xlib iq *
    }

    UnregisterElement $xlib error    http://etherx.jabber.org/streams
    UnregisterElement $xlib features http://etherx.jabber.org/streams

    unset state
    return
}

proc ::xmpp::status {xlib {status ""}} {
    variable $xlib
    upvar 0 $xlib state

    if {![info exists $xlib]} {
        return ""
    } elseif {![string equal $status ""]} {
        return [string equal $state(status) $status]
    } else {
        return $state(status)
    }
}

proc ::xmpp::connect {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    set transport tcp
    set host      localhost
    set port      5222
    set argList   {}

    foreach {key val} $args {
        switch -- $key {
            -transport {set transport $val}
            -host      {set host      $val}
            -port      {set port      $val}
            -command   {set cmd       $val}
            default    {lappend argList $key $val}
        }
    }

    Debug 2 $xlib "$host $port $transport"

    if {![info exists cmd]} {
        # Propagate error (if any) up
        set state(transport) \
            [eval [list transport::open $transport $host $port \
                        -streamHeaderCommand \
                                [namespace code [list GotStream $xlib ok]] \
                        -streamTrailerCommand \
                                [namespace code [list EndOfParse $xlib]] \
                        -stanzaCommand \
                                [namespace code [list Parse $xlib]] \
                        -eofCommand \
                                [namespace code [list EndOfFile $xlib]]] \
                        $argList]
        set state(status) connected
        return $xlib
    } else {
        set ttoken \
            [eval [list transport::open $transport $host $port \
                        -streamHeaderCommand \
                                [namespace code [list GotStream $xlib ok]] \
                        -streamTrailerCommand \
                                [namespace code [list EndOfParse $xlib]] \
                        -stanzaCommand \
                                [namespace code [list Parse $xlib]] \
                        -eofCommand \
                                [namespace code [list EndOfFile $xlib]] \
                        -command \
                                [namespace code [list ConnectAux $xlib $cmd]]] \
                        $argList]
        return $ttoken
    }
}

proc ::xmpp::ConnectAux {xlib cmd status msg} {
    variable $xlib
    upvar 0 $xlib state

    if {[string equal $status ok]} {
        set state(transport) $msg
        set state(status) connected
        uplevel #0 $cmd [list ok $xlib]
    } else {
        uplevel #0 $cmd [list $status $msg]
    }
    return
}

######################################################################

proc ::xmpp::ReopenStream {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$args"

    transport::use $state(transport) reset

    # Unset features variable to remove possible trace.
    array unset state features

    if {[info exists state(-version)]} {
        set vargs [list -version $state(-version)]
    } else {
        set vargs {}
    }

    eval [list openStream $xlib $state(server) \
                                -xmlns:stream $state(-xmlns:stream) \
                                -xmlns $state(-xmlns) \
                                -xml:lang $state(-xml:lang)] $vargs $args
}

# Bugs:
#       Only stream XMLNS http://etherx.jabber.org/streams is supported.
#       Though there's no other defined stream XMLNS currently.

proc ::xmpp::openStream {xlib server args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$server $args"

    set state(server) $server

    array set params [list -xmlns:stream http://etherx.jabber.org/streams \
                           -xmlns jabber:client \
                           -xml:lang [xml::lang]]

    array set state [array get params]

    set timeout 0
    foreach {key val} $args {
        switch -- $key {
            -xmlns:stream {
                if {![string equal $val http://etherx.jabber.org/streams]} {
                    return -code error \
                           -errorinfo [::msgcat::mc \
                                           "Unsupported stream XMLNS \"%s\"" \
                                           $val]
                }
            }
            -xmlns -
            -xml:lang -
            -version {
                set state($key) $val
                set params($key) $val
            }
            -timeout {
                set timeout $val
            }
            -command {
                set state(openStreamCommand) $val
            }
            default  {
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {$timeout > 0} {
        set state(streamAfterId) \
            [after $timeout [namespace code [list GotStream $xlib timeout {}]]]
    }

    eval [list transport::use $state(transport) openStream $server] \
         [array get params]

    if {[info exists state(openStreamCommand)]} {
        # Asynchronous mode
        return $xlib
    } else {
        # Synchronous mode
        vwait $xlib\(openStatus)

        if {![string equal $state(openStatus) timeout]} {
            return $state(sessionID)
        } else {
            return -code error $state(sessionID)
        }
    }
}

proc ::xmpp::GotStream {xlib status attrs} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$status $attrs"

    if {[info exists state(openStreamCommand)]} {
        set cmd $state(openStreamCommand)
        unset state(openStreamCommand)
    }

    if {[info exists state(streamAfterId)]} {
        after cancel $state(streamAfterId)
        unset state(streamAfterId)
    }

    if {[string equal $status timeout]} {
        set state(sessionID) [::msgcat::mc "Timeout while opening stream"]
        # Trigger vwait in [openStream] in synchronous mode
        set state(openStatus) $status

        if {[info exists cmd]} {
            # Invoke callback in asynchronous mode
            uplevel #0 $cmd [list $status $state(sessionID)]
        }
        return
    }

    if {[xml::isAttr $attrs from]} {
        # Sometimes server (ejabberd is known to) returns 'from'
        # attribute which differs from 'to' attribute sent to the server.
        # If XMLNS is 'jabber:component:accept' then the address in 'from'
        # attribute is ignored.

        if {![string equal $state(-xmlns) jabber:component:accept]} {
            set state(server) [xml::getAttr $attrs from]
        }
    }

    set version [xml::getAttr $attrs version]
    if {![string is double -strict $version]} {
        set version 0.0
    }

    set sessionID [xml::getAttr $attrs id]

    Debug 2 $xlib "server = $state(server), sessionID = $sessionID,\
                   version = $version"

    if {$version < 1.0} {
        # Register iq-auth and iq-register namespaces to allow
        # authenticate and register in-band on non-XMPP server
        ParseStreamFeatures $xlib \
            [xml::create features \
                  -xmlns http://etherx.jabber.org/streams \
                  -subelement \
                      [xml::create auth \
                            -xmlns http://jabber.org/features/iq-auth] \
                  -subelement \
                      [xml::create register \
                            -xmlns http://jabber.org/features/iq-register]]
    }

    set state(status) streamOpened

    set state(sessionID) $sessionID
    # Trigger vwait in [openStream] in synchronous mode
    set state(openStatus) $status

    if {[info exists cmd]} {
        # Invoke callback in asynchronous mode
        uplevel #0 $cmd [list $status $sessionID]
    }
    return
}

proc ::xmpp::server {xlib} {
    variable $xlib
    upvar 0 $xlib state

    return $state(server)
}

######################################################################

proc ::xmpp::TraceStreamFeatures {xlib cmd} {
    variable $xlib
    upvar 0 $xlib state

    if {[info exists state(features)]} {
        after idle $cmd [list $state(features)]
    } else {
        # Variable state(features) must not be set outside ParseStreamFeatures,
        # to prevent spurious trace callback triggering.
        trace variable $xlib\(features) w \
              [namespace code [list TraceStreamFeaturesAux $xlib $cmd]]
    }
    return
}

proc ::xmpp::TraceStreamFeaturesAux {xlib cmd args} {
    variable $xlib
    upvar 0 $xlib state

    trace vdelete $xlib\(features) w \
          [namespace code [list TraceStreamFeaturesAux $xlib $cmd]]

    uplevel #0 $cmd [list $state(features)]
    return
}

proc ::xmpp::RemoveTraceStreamFeatures {xlib cmd} {
    variable $xlib
    upvar 0 $xlib state

    trace vdelete $xlib\(features) w \
          [namespace code [list TraceStreamFeaturesAux $xlib $cmd]]

    return
}

######################################################################

proc ::xmpp::ParseStreamFeatures {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$xmlElement"

    xml::split $xmlElement tag xmlns attrs cdata subels

    set state(features) $subels
    return
}

proc ::xmpp::ParseStreamError {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$xmlElement"

    client $xlib errorMsg [streamerror::message $xmlElement]
    return
}

######################################################################

proc ::xmpp::SwitchTransport {xlib transport} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$transport"

    set state(transport) \
        [transport::switch $state(transport) $transport]
}

######################################################################

proc ::xmpp::outXML {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$xmlElement"
    ::LOG_OUTPUT_XML $xlib $xmlElement

    transport::use $state(transport) outXML $xmlElement
}

proc ::xmpp::outText {xlib text} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$text"
    ::LOG_OUTPUT $xlib $text

    transport::use $state(transport) outText $xmlElement
}

######################################################################

proc ::xmpp::closeStream {xlib} {
    variable $xlib
    upvar 0 $xlib state

    set msg [xml::streamTrailer]
    Debug 2 $xlib "$msg"
    ::LOG_OUTPUT $xlib $msg

    transport::use $state(transport) closeStream
}

######################################################################

proc ::xmpp::EndOfParse {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            after idle [namespace code [list ForcedDisconnect $xlib]]
        }
    }
}

proc ::xmpp::EndOfFile {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            after idle [namespace code [list ForcedDisconnect $xlib]]
        }
    }
}

proc ::xmpp::ForcedDisconnect {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            set state(status) disconnecting

            catch {
                transport::use $state(transport) close
            }

            client $xlib disconnect

            ClearState $xlib
        }
    }
}

proc ::xmpp::disconnect {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            set state(status) disconnecting

	    catch {
                closeStream $xlib
                transport::use $state(transport) close
	    }

            ClearState $xlib
        }
    }
}

######################################################################

proc ::xmpp::ClearState {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib ""

    foreach idx [array names state {iq *}] {
        set cmd $state($idx)
        unset state($idx)

        uplevel #0 $cmd [list abort \
                              [xml::create error \
                                   -cdata [::msgcat::mc "Disconnected"]]]
    }

    set state(id) 0
    set state(status) disconnected

    # connect
    array unset state transport

    # openStream
    array unset state server
    array unset state -xmlns:stream
    array unset state -xmlns
    array unset state -xml:lang
    array unset state -version
    array unset state openStreamCommand
    array unset state streamAfterId
    array unset state openStatus
    array unset state sessionID

    # TraceStreamFeatures
    array unset state features 
}

######################################################################

proc ::xmpp::RegisterElement {xlib tag xmlns cmd} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$tag $xmlns $cmd"

    if {![info exists state([list registered $tag $xmlns])]} {
        set state([list registered $tag $xmlns]) {}
    }
    lappend state([list registered $tag $xmlns]) $cmd
    return
}

proc ::xmpp::UnregisterElement {xlib tag xmlns} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$tag $xmlns"

    if {[info exists state([list registered $tag $xmlns])]} {
        set state([list registered $tag $xmlns]) \
            [lreplace $state([list registered $tag $xmlns]) end end]

        if {[llength $state([list registered $tag $xmlns])] == 0} {
            unset state([list registered $tag $xmlns])
        }
    }
    return
}

proc ::xmpp::ElementCommand {xlib tag xmlns} {
    variable $xlib
    upvar 0 $xlib state

    # If there's an exact match, return it
    if {[info exists state([list registered $tag $xmlns])]} {
        return [lindex $state([list registered $tag $xmlns]) end]
    }

    # Otherwise find matching indices
    foreach idx [lsort [array names state {registered *}]] {
        foreach {ptype ptag pxmlns} $idx break

        if {[string equal $ptype registered] && \
                [string match $ptag $tag] && \
                [string match $pxmlns $xmlns]} {
            return [lindex $state($idx) end]
        }
    }

    # There's no matches
    return
}

######################################################################

proc ::xmpp::Parse {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$xmlElement"
    ::LOG_INPUT_XML $xlib $xmlElement

    if {![info exists state(transport)]} {
        Debug 1 $xlib "Connection doesn't exist"
        return -1
    }

    xml::split $xmlElement tag xmlns attrs cdata subels

    set cmd [ElementCommand $xlib $tag $xmlns]
    if {[string length $cmd] > 0} {
        uplevel #0 $cmd [list $xmlElement]
        return
    }

    client $xlib packet $xmlElement
    return
}

proc ::xmpp::ParseMessage {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    xml::split $xmlElement tag xmlns attrs cdata subels

    set from   ""
    set type   ""
    set x      {}
    set params {}
    set xparam {}

    foreach {key val} $attrs {
        switch -- $key {
            from     {set from $val}
            type     {set type $val}
            xml:lang {lappend params -lang $val}
            to       {lappend params -to   $val}
            id       {lappend params -id   $val}
            default  {lappend xparam $key  $val}
        }
    }

    foreach subel $subels {
        xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            subject {lappend params -subject $scdata}
            thread  {lappend params -thread  $scdata}
            body    {lappend params -body    $scdata}
            error   {lappend params -error   $subel}
            default {lappend x $subel}
        }
    }

    eval [list client $xlib message $from $type $x -x $xparam] $params
}

proc ::xmpp::ParsePresence {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    xml::split $xmlElement tag xmlns attrs cdata subels

    set from   ""
    set type   ""
    set x      {}
    set params {}
    set xparam {}

    foreach {key val} $attrs {
        switch -- $key {
            from     {set from $val}
            type     {set type $val}
            xml:lang {lappend params -lang $val}
            to       {lappend params -to   $val}
            id       {lappend params -id   $val}
            default  {lappend xparam $key  $val}
        }
    }

    foreach subel $subels {
        xml::split $subel stag sxmlns sattrs scdata ssubels

        switch $stag {
            priority {lappend params -priority $scdata}
            show     {lappend params -show     $scdata}
            status   {lappend params -status   $scdata}
            error    {lappend params -error    $subel}
            default  {lappend x $subel}
        }
    }

    eval [list client $xlib presence $from $type $x -x $xparam] $params
}

proc ::xmpp::ParseIQ {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib $xmlElement

    xml::split $xmlElement tag xmlns attrs cdata subels

    set to     ""
    set from   ""
    set type   ""
    set id     ""
    set x      {}
    set params {}
    set xparam {}

    foreach {key val} $attrs {
        switch -- $key {
            from     {set from $val}
            type     {set type $val}
            xml:lang {lappend params -lang $val}
            id       {
                set id $val
                lappend params -id $val
            }
            to       {
                set to $val
                lappend params -to $val
            }
            default  {lappend xparam $key $val}
        }
    }

    # A 'from' JID in result or error IQ may differ from 'to' JID in
    # corresponding request if the reques was sent without 'to' attribute.
    if {[::xmpp::jid::equal $from $to]} {
        set pfrom [list $from ""]
    } elseif {[::xmpp::jid::equal $from [::xmpp::jid::stripResource $to]]} {
        set pfrom [list $from ""]
    } elseif {[::xmpp::jid::equal $from [::xmpp::jid::server $to]]} {
        set pfrom [list $from ""]
    } else {
        set pfrom [list $from]
    }

    switch -- $type {
        get -
        set {
            eval [list iq::process $xlib $from $type \
                                   [lindex $subels 0]] $params
        }
        result {
            foreach from $pfrom {
                if {[info exists state([list iq $id $from])]} {
                    set cmd $state([list iq $id $from])
                    unset state([list iq $id $from])

                    uplevel #0 $cmd [list ok [lindex $subels 0]]
                    return
                }
            }

            Debug 2 $xlib [::msgcat::mc "IQ id doesn't exists in memory"]
            return
        }
        error {
            foreach from $pfrom {
                if {[info exists state([list iq $id $from])]} {
                    set cmd $state([list iq $id $from])
                    unset state([list iq $id $from])

                    set error {}
                    foreach subel $subels {
                        xml::split $subel stag sxmlns sattrs scdata ssubels
                        if {[string equal $stag error]} {
                            set error $subel
                            break
                        }
                    }

                    uplevel #0 $cmd [list error $error]
                    return
                }
            }

            Debug 2 $xlib [::msgcat::mc "IQ id doesn't exists in memory"]
            return
        }
        default {
            Debug 2 $xlib [::msgcat::mc "Unknown IQ type \"%s\"" $type]
            return
        }
    }
}

######################################################################
proc ::xmpp::sendMessage {xlib to args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$to $args"

    if {![info exists state(transport)]} {
        Debug 1 $xlib "Connection doesn't exist"
        return -1
    }

    set attrs(to) $to
    set attrs(xml:lang) [xml::lang]
    set subelements [list]

    foreach {key val} $args {
        switch -- $key {
            -from    {set attrs(from) $val}
            -type    {set attrs(type) $val}
            -id      {set attrs(id)   $val}
            -subject {lappend subelements [xml::create subject -cdata $val]}
            -thread  {lappend subelements [xml::create thread  -cdata $val]}
            -body    {lappend subelements [xml::create body    -cdata $val]}
            -error   {lappend subelements $val}
            -xlist {
                foreach x $val {
                    lappend subelements $x
                }
            }
        }
    }

    set data [xml::create message -attrs [array get attrs] \
                                  -subelements $subelements]
    ::LOG_OUTPUT_XML $xlib $data
    outXML $xlib $data
    return
}

######################################################################
proc ::xmpp::sendPresence {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$args"

    if {![info exists state(transport)]} {
        Debug 1 $xlib "Connection doesn't exist"
        return -1
    }

    set attrs(xml:lang) [xml::lang]
    set subelements {}

    foreach {key val} $args {
        switch -- $key {
            -from     {set attrs(from) $val}
            -to       {set attrs(to)   $val}
            -type     {set attrs(type) $val}
            -id       {set attrs(id)   $val}
            -show     {lappend subelements [xml::create show     -cdata $val]}
            -status   {lappend subelements [xml::create status   -cdata $val]}
            -priority {lappend subelements [xml::create priority -cdata $val]}
            -error    {lappend subelements $val}
            -xlist {
                foreach x $val {
                    lappend subelements $x
                }
            }
        }
    }

    set data [xml::create presence -attrs [array get attrs] \
                                   -subelements $subelements]
    ::LOG_OUTPUT_XML $xlib $data
    outXML $xlib $data
    return
}

######################################################################

proc ::xmpp::sendIQ {xlib type args} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$type $args"

    switch -- $type {
        get -
        set {
            set attrs(type) $type
            set getset 1
        }
        result -
        error   {
            set attrs(type) $type
            set getset 0
        }
        default {
            set attrs(type) get
            set getset 1
        }
    }

    set attrs(xml:lang) [xml::lang]
    set subelements {}

    set timeout 0

    set to [xml::getAttr $args -to]

    foreach {key val} $args {
        switch -- $key {
            -from {set attrs(from) $val}
            -to   {set attrs(to)   $val}
            -id {
                # Option -command takes precedence over -id
                if {![info exists attrs(id)] || ![info exists cmd]} {
                    set attrs(id) $val
                }
            }
            -command {
                # Option -command makes sense for get or set IQs only
                if {!$getset} {
                    return -code error \
                           -errorinfo [::msgcat::mc "Option \"-command\" is\
                                                     illegal for IQ type\
                                                     \"%s\"" $attrs(type)]
                }

                # Only the last -command takes effect
                if {![info exists attrs(id)] || ![info exists cmd]} {
                    set attrs(id) [incr state(id)]
                }
                set cmd $val
            }
            -timeout {
                if {$val > 0} {
                    set timeout $val
                }
            }
            -query -
            -error {lappend subelements $val}
        }
    }

    if {![info exists state(transport)]} {
        Debug 1 $xlib "Connection doesn't exist"
        if {[info exists cmd]} {
            uplevel #0 $cmd [list abort \
                                  [xml::create error \
                                        -cdata [::msgcat::mc "Disconnected"]]]
        }
        return -1
    }

    if {[info exists cmd]} {
        set state([list iq $attrs(id) $to]) $cmd
        if {$timeout > 0} {
            after $timeout \
                  [namespace code [list abortIQ $xlib $attrs(id) timeout \
                                [::msgcat::mc "IQ %s timed out" $attrs(id)]]]
        }
    }

    set data [xml::create iq -attrs [array get attrs] \
                             -subelements $subelements]

    ::LOG_OUTPUT_XML $xlib $data
    outXML $xlib $data

    if {$getset && [info exists attrs(id)]} {
        return $attrs(id)
    } else {
        return
    }
}

######################################################################

# status: abort, timeout

proc ::xmpp::abortIQ {xlib id status error} {
    variable $xlib
    upvar 0 $xlib state

    Debug 2 $xlib "$id"

    foreach idx [array names state [list iq $id *]] {
        set cmd $state($idx)
        unset state($idx)

        uplevel #0 $cmd [list $status $error]
    }
}

######################################################################
#
proc ::LOG {text} {
#
# For debugging purposes.
#
    puts "LOG: $text\n"
}

proc ::LOG_OUTPUT      {connid t} {}
proc ::LOG_OUTPUT_XML  {connid x} {}
proc ::LOG_OUTPUT_SIZE {connid x size} {}
proc ::LOG_INPUT       {connid t} {}
proc ::LOG_INPUT_XML   {connid x} {}
proc ::LOG_INPUT_SIZE  {connid x size} {}

# ::xmpp::Debug --
#
#       Prints debug information.
#
# Arguments:
#       level   A debug level.
#       str     A debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::xmpp::debug variable is not less than num.

proc ::xmpp::Debug {level xlib str} {
    variable debug

    if {$debug >= $level} {
        puts "[lindex [info level -1] 0] $xlib: $str"
    }

    return
}

######################################################################
######################################################################
######################################################################

proc ::xmpp::socket_ip {connid} {
    variable lib

    if {[info exists lib($connid,sck)] && \
        ![catch {fconfigure $lib($connid,sck) -sockname} sock]} {
        return [lindex $sock 0]
    } else {
        return ""
    }
}

# vim:ts=8:sw=4:sts=4:et
