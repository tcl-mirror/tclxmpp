# xmpp.tcl --
#
#       This file is part of the XMPP library. It implements the main library
#       routines.
#
# Copyright (c) 2008-2009 Sergei Golovan <sgolovan@nes.ru>
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

    # Default debug level (0: no debug, 1: light debug, 2: heavy debug).

    variable debug 0
}

# ::xmpp::new --
#
#       Create a new XMPP token and assigns client callbacks for XMPP events.
#
# Arguments:
#       token                   (optional, if missing then token is created
#                               automatically, if present then it must be a
#                               fully namespaced nonexistent variable) XMPP
#                               token to create.
#       -packetcommand     cmd  (optional) Command to call on every incoming
#                               XMPP packet except stream errors.
#       -messagecommand    cmd  (optional) Command to call on every XMPP
#                               message packet (overrides -packetCommand).
#       -presencecommand   cmd  (optional) Command to call on every XMPP
#                               presence packet (overrides -packetCommand).
#       -disconnectcommand cmd  (optional) Command to call on forced disconnect
#                               from XMPP server.
#       -statuscommand     cmd  (optional) Command to call when XMPP connection
#                               status is changed (e.g. after successful
#                               authentication).
#       -errorcommand      cmd  (optional) Command to call on XMPP stream error
#                               packet.
#
# Result:
#       XMPP token name or error if the supplied variable exists or illegal
#       option is listed.
#
# Side effects:
#       A new variable is created.

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
                   [::msgcat::mc "An existing variable \"%s\" cannot be used\
                                  as an XMPP token" $xlib]
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
            -packetcommand -
            -messagecommand -
            -presencecommand -
            -iqcommand -
            -disconnectcommand -
            -statuscommand -
            -errorcommand -
	    -logcommand {
                set attrs($key) $val
            }
            default {
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    variable $xlib
    upvar 0 $xlib state

    array unset state
    set state(status) disconnected

    # A sequence of IQ ids
    set state(id) 0

    array set state [array get attrs]

    if {[info exists state(-messagecommand)]} {
        RegisterElement $xlib message * \
                        [namespace code [list ParseMessage $xlib]]
    }
    if {[info exists state(-presencecommand)]} {
        RegisterElement $xlib presence * \
                        [namespace code [list ParsePresence $xlib]]
    }
    if {![info exists state(-packetcommand)] || \
                                    [info exists state(-iqcommand)]} {
        RegisterElement $xlib iq * \
                        [namespace code [list ParseIQ $xlib]]
    }

    RegisterElement $xlib error http://etherx.jabber.org/streams \
                    [namespace code [list ParseStreamError $xlib]]
    RegisterElement $xlib features http://etherx.jabber.org/streams \
                    [namespace code [list ParseStreamFeatures $xlib]]

    Debug $xlib 2 ""

    return $xlib
}

# ::xmpp::free --
#
#       Destroy an existing XMPP token.
#
# Arguments:
#       xlib            XMPP token to destroy.
#
# Result:
#       Empty string or error if the token is still connected.
#
# Side effects:
#       The variable which contains token state is destroyed.

proc ::xmpp::free {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    if {![status $xlib disconnected]} {
        return -code error [::msgcat::mc "Free without disconnect"]
    }

    if {[info exists state(-messagecommand)]} {
        UnregisterElement $xlib message *
    }
    if {[info exists state(-presencecommand)]} {
        UnregisterElement $xlib presence *
    }
    if {![info exists state(-packetcommand)]} {
        UnregisterElement $xlib iq *
    }

    UnregisterElement $xlib error    http://etherx.jabber.org/streams
    UnregisterElement $xlib features http://etherx.jabber.org/streams

    unset state
    return
}

# ::xmpp::connect --
#
#       Connect to XMPP server.
#
# Arguments:
#       xlib                    XMPP token.
#       host                    (optional, defaults to "localhost") Server name
#                               to connect. It isn't used when transport is
#                               "poll".
#       port                    (optional, defaults to 5222) Port to connect.
#                               It isn't used for "poll" transport.
#       -transport transport    (optional, defaults to "tcp") Transport to use
#                               when connecting to an XMPP server. May be one
#                               of "tcp", "tls", "poll", "zlib" (though none of
#                               the servers support zlib compressed sockets
#                               without prior negotiating).
#       -command cmd            (optional) If present then the connection
#                               becomes asynchronous and the command is called
#                               upon connection success or failure. Otherwise
#                               the connection is in synchronous mode.
#       Other arguments are passed unchanged to corresponding transport open
#       routine.
#
# Result:
#       Empty string on success or error on failure in synchronous mode.
#       Connection token to make it possible to abort connection in
#       asynchronous mode.
#
# Side effects:
#       A new connection to an XMPP server is started (or is opened). In
#       synchronous mode connection status is set to "connected". In
#       asynchronous mode an abort command is stored to be called if a user
#       will decide to abort connection procedure.

proc ::xmpp::connect {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    if {![string equal $state(status) disconnected]} {
        # TODO: Should we use ForcedDisconnect or call back?
        disconnect $xlib
    }

    set transport tcp
    set host      localhost
    set port      5222
    set argList   {}

    if {![string match -* [lindex $args 0]]} {
        set host [lindex $args 0]
        set args [lrange $args 1 end]
    }

    if {![string match -* [lindex $args 0]]} {
        set port [lindex $args 0]
        set args [lrange $args 1 end]
    }

    foreach {key val} $args {
        switch -- $key {
            -transport {set transport $val}
            -command   {set cmd       $val}
            default    {lappend argList $key $val}
        }
    }

    Debug $xlib 2 "$host $port $transport"

    if {![info exists cmd]} {
        # TODO: Allow abortions in synchronous mode too.

        # Propagate error (if any) up.
        set state(transport) \
            [eval [list transport::open $transport $host $port \
                        -streamheadercommand \
                                [namespace code [list GotStream $xlib ok]] \
                        -streamtrailercommand \
                                [namespace code [list EndOfParse $xlib]] \
                        -stanzacommand \
                                [namespace code [list Parse $xlib]] \
                        -eofcommand \
                                [namespace code [list EndOfFile $xlib]]] \
                        $argList]

        set state(status) connected
        return
    } else {
        set token \
            [eval [list transport::open $transport $host $port \
                        -streamheadercommand \
                                [namespace code [list GotStream $xlib ok]] \
                        -streamtrailercommand \
                                [namespace code [list EndOfParse $xlib]] \
                        -stanzacommand \
                                [namespace code [list Parse $xlib]] \
                        -eofcommand \
                                [namespace code [list EndOfFile $xlib]] \
                        -command \
                                [namespace code [list ConnectAux $xlib $cmd]]] \
                        $argList]

        set state(abortCommand) \
            [namespace code [list transport::use $token abort]]
        return $token
    }
}

# ::xmpp::ConnectAux --
#
#       A helper procedure which calls back with connection to XMPP server
#       result.
#
# Arguments:
#       xlib            XMPP token.
#       cmd             Callback to call.
#       status          "ok", "error", "abort", or "timeout".
#       msg             Transport token in case of success or error message in
#                       case of failure.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called and a stored abort command is emptied (it is no
#       longer needed as the connect procedure is finished).

proc ::xmpp::ConnectAux {xlib cmd status msg} {
    variable $xlib
    upvar 0 $xlib state

    catch {unset state(abortCommand)}

    if {[string equal $status ok]} {
        set state(transport) $msg
        set state(status) connected
        uplevel #0 $cmd [list ok ""]
    } else {
        uplevel #0 $cmd [list $status $msg]
    }
    return
}

# ::xmpp::openStream --
#
#       Open XMPP stream over the already opened connection.
#
# Arguments:
#       xlib            XMPP token.
#       server          XMPP server to which the stream is opened.
#       -xmlns:stream ns (optional, defaults to
#                       http://etherx.jabber.org/streams, if present must be
#                       http://etherx.jabber.org/streams). XMLNS for stream
#                       prefix.
#       -xmlns xmlns    (optional, defaults to jabber:client) Stream default
#                       XMLNS.
#       -xml:lang lang  (optional, defaults to language from msgcat
#                       preferences) Stream default xml:lang attribute.
#       -version ver    (optional) Stream XMPP version. Must be "1.0" if any
#                       XMPP feature is used (SASL, STARTTLS, stream
#                       compression).
#       -timeout num    (optional, defaults to 0 which means infinity) Timeout
#                       after which the operation is finished with failure.
#       -command cmd    (optional) If present then the stream opens in
#                       asynchronous mode and the command "cmd" is called upon
#                       success or failure. Otherwise the mode is synchronous.
#
# Result:
#       The same as in [OpenStreamAux].
#
# Side effects:
#       The same as in [OpenStreamAux]. Also, server state variable is set.

proc ::xmpp::openStream {xlib server args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$server $args"

    set state(server) $server

    eval [list OpenStreamAux $xlib] $args
}

# ::xmpp::ReopenStream --
#
#       Reset underlying XML parser and reopen XMPP stream. This procedure
#       is useful when changing transport (from tcp to tls or zlib) and
#       when resetting stream after SASL authentication. It's never called
#       by user directly.
#
# Arguments:
#       xlib            XMPP token.
#       args            Additional arguments to pass to OpenStreamAux. They are
#                       the same as for [openStream]. But usually the only
#                       useful options are -command and -timeout.
#
# Result:
#       The same as in [OpenStreamAux].
#
# Side effects:
#       In addition to [OpenStreamAux] side effects, an XML parser in transport
#       is reset.

proc ::xmpp::ReopenStream {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$args"

    transport::use $state(transport) reset

    # Unset features variable to remove possible trace.
    array unset state features

    if {[info exists state(-version)]} {
        set vargs [list -version $state(-version)]
    } else {
        set vargs {}
    }

    eval [list OpenStreamAux $xlib \
                             -xmlns:stream $state(-xmlns:stream) \
                             -xmlns $state(-xmlns) \
                             -xml:lang $state(-xml:lang)] $vargs $args
}

# ::xmpp::OpenStreamAux --
#
#       A helper procedure which contains common code for opening and
#       reopening XMPP streams.
#
# Arguments:
#       The same as for openStream (except server which is taken from state
#       variable).
#
# Result:
#       Empty string in asynchronous mode, session id or error in synchronous
#       mode.
#
# Side effects:
#       Stream header is sent to an open channel. An abort command is stored
#       to be called if a user will decide to abort stream opening procedure.
#
# Bugs:
#       Only stream XMLNS http://etherx.jabber.org/streams is supported.
#       On the other hand there's no other defined stream XMLNS currently.

proc ::xmpp::OpenStreamAux {xlib args} {
    variable $xlib
    upvar 0 $xlib state

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
                           [::msgcat::mc "Unsupported stream XMLNS \"%s\"" \
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
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {$timeout > 0} {
        set state(streamAfterId) \
            [after $timeout [namespace code [list GotStream $xlib timeout {}]]]
    }

    # Stream may be reopened inside STARTTLS, or compression, or SASL
    # procedure, so set abort command only if it isn't defined already.

    if {![info exists state(abortCommand)]} {
        set state(abortCommand) \
            [namespace code [list GotStream $xlib abort {}]]
    }

    eval [list transport::use $state(transport) openStream $state(server)] \
         [array get params]

    if {[info exists state(openStreamCommand)]} {
        # Asynchronous mode
        return ""
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

# ::xmpp::GotStream --
#
#       A helper procedure which is invoked when an incoming XMPP stream
#       header is parsed by a transport. It finishes headers exchange.
#
# Arguments:
#       xlib            XMPP token.
#       status          "ok", "abort", or "timeout".
#       attrs           List of XMPP stream attributes.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called in asynchronous mode or [vwait] is triggered
#       in synchronous mode. Also, a stored abort command is emptied (it is no
#       longer needed as the connect procedure is finished).

proc ::xmpp::GotStream {xlib status attrs} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$status $attrs"
    if {[string equal $status ok]} {
	set msg "<stream:stream "
	foreach {attr val} $attrs {
	    append msg " $attr='[xml::Escape $val]'"
	}
	append msg ">"
	CallBack $xlib log input text $msg
    }

    if {[info exists state(openStreamCommand)]} {
        set cmd $state(openStreamCommand)
        unset state(openStreamCommand)
    }

    if {[info exists state(streamAfterId)]} {
        after cancel $state(streamAfterId)
        unset state(streamAfterId)
    }

    # Stream may be reopened inside STARTTLS, or compression, or SASL
    # procedure, so unset abort command only if it was set in [openStream]

    if {[string equal $state(abortCommand) \
                      [namespace code [list GotStream $xlib abort {}]]]} {
        catch {unset state(abortCommand)}
    }

    switch -- $status {
        timeout {
            set state(sessionID) [::msgcat::mc "Opening stream timed out"]

            # Trigger vwait in [openStream] in synchronous mode
            set state(openStatus) $status

            if {[info exists cmd]} {
                # Invoke callback in asynchronous mode
                uplevel #0 $cmd [list $status $state(sessionID)]
            }
            return
        }
        abort {
            set state(sessionID) [::msgcat::mc "Opening stream aborted"]

            # Trigger vwait in [openStream] in synchronous mode
            set state(openStatus) $status

            if {[info exists cmd]} {
                # Invoke callback in asynchronous mode
                uplevel #0 $cmd [list $status $state(sessionID)]
            }
            return
        }
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

    Debug $xlib 2 "server = $state(server), sessionID = $sessionID,\
                   version = $version"

    if {$version < 1.0} {
        # Register iq-auth and iq-register namespaces to allow
        # authenticate and register in-band on pre-XMPP server
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

# ::xmpp::ParseStreamFeatures --
#
#       A helper procedure which is called when stream features are received.
#       It stores features list (as a list of XML elements, because it may be
#       a deep list) in a variable. This procedure is registered as a handler
#       for features element in http://etherx.jabber.org/streams XMLNS in
#       [new].
#
# Arguments:
#       xlib            XMPP token.
#       xmlElement      Features XML element to store.
#
# Result:
#       Empty string.
#
# Side effects:
#       Features list is stored in a state variable.

proc ::xmpp::ParseStreamFeatures {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$xmlElement"

    xml::split $xmlElement tag xmlns attrs cdata subels

    set state(features) $subels
    return
}

# ::xmpp::TraceStreamFeatures --
#
#       Call the specified command back if stream features are already
#       received, or set a trace to call the command upon receiving them.
#       Trace syntax is old-style to make it work in Tcl 8.3.
#
# Arguments:
#       xlib            XMPP token.
#       cmd             Command to call.
#
# Result:
#       Empty string.
#
# Side effects:
#       If stream features aren't received yet then a trace is added for
#       variable state(features).

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

# ::xmpp::TraceStreamFeaturesAux --
#
#       A helper procedure which is called by a trace of state(features)
#       variable. It in turn removes trace and calls a specified command back.
#       Trace syntax is old-style to make it work in Tcl 8.3.
#
# Arguments:
#       xlib            XMPP token.
#       cmd             Command to call.
#       args            Arguments, added by trace.
#
# Result:
#       Empty string.
#
# Side effects:
#       Trace of state(features) variable is removed.

proc ::xmpp::TraceStreamFeaturesAux {xlib cmd args} {
    variable $xlib
    upvar 0 $xlib state

    RemoveTraceStreamFeatures $xlib $cmd

    uplevel #0 $cmd [list $state(features)]
    return
}

# ::xmpp::RemoveTraceStreamFeatures --
#
#       Remove trace of state(features) variable if it's set. This procedure
#       may be called in case if it's needed to abort connection process, or
#       in case when stream features are received (see
#       [TraceStreamFeaturesAux]).
#
# Arguments:
#       xlib            XMPP token.
#       cmd             Command that was to be called.
#
# Result:
#       Empty string.
#
# Side effects:
#       Trace of state(features) is removed if it was set.

proc ::xmpp::RemoveTraceStreamFeatures {xlib cmd} {
    variable $xlib
    upvar 0 $xlib state

    trace vdelete $xlib\(features) w \
          [namespace code [list TraceStreamFeaturesAux $xlib $cmd]]

    return
}

# ::xmpp::ParseStreamError --
#
#       A helper procedure which is called when stream error is received.
#       It calls back error command (-errorcommand option in [new]) with
#       appended error message. This procedure is registered as a handler
#       for error element in http://etherx.jabber.org/streams XMLNS in [new].
#
# Arguments:
#       xlib            XMPP token.
#       xmlElement      Stream error XML element.
#
# Result:
#       Empty string.
#
# Side effects:
#       A client error callback is invoked.

proc ::xmpp::ParseStreamError {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$xmlElement"

    CallBack $xlib error [streamerror::condition $xmlElement] \
                         [streamerror::message $xmlElement]
    return
}

# ::xmpp::SwitchTransport --
#
#       Switch XMPP transport. This procedure is helpful if STARTTLS or
#       stream compression over TCP is used.
#
# Arguments:
#       xlib            XMPP token.
#       transport       Transport name to switch to.
#
# Result:
#       Empty string or error.
#
# Side effects:
#       Transport is changed if it's possible.

proc ::xmpp::SwitchTransport {xlib transport args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$transport"

    set state(transport) \
        [eval [list transport::switch $state(transport) $transport] $args]
    return
}

# ::xmpp::outXML --
#
#       Output XML element to an XMPP channel.
#
# Arguments:
#       xlib            XMPP token.
#       xmlElement      XML element to send.
#
# Result:
#       Length of the sent textual XML representation.
#
# Side effects:
#       XML element is sent to the server.

proc ::xmpp::outXML {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "[xml::toText $xmlElement]"
    CallBack $xlib log output xml $xmlElement

    transport::use $state(transport) outXML $xmlElement
}

# ::xmpp::outText --
#
#       Output text string to an XMPP channel. If the text doesn't represent
#       valid XML then server will likely disconnect the XMPP session.
#
# Arguments:
#       xlib            XMPP token.
#       text            Text to send.
#
# Result:
#       Length of the sent XML textual representation.
#
# Side effects:
#       XML element is sent to the server.

proc ::xmpp::outText {xlib text} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$text"
    CallBack $xlib log output text $text

    transport::use $state(transport) outText $text
}

# ::xmpp::closeStream --
#
#       Close XMPP stream (usually by sending </stream:stream>).
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Length of the sent stream trailer.
#
# Side effects:
#       XMPP stream trailer is sent to the server.

proc ::xmpp::closeStream {xlib} {
    variable $xlib
    upvar 0 $xlib state

    set msg [xml::streamTrailer]
    Debug $xlib 2 "$msg"
    CallBack $xlib log output text $msg

    transport::use $state(transport) closeStream
}

# ::xmpp::EndOfParse --
#
#       A callback procedure which is called if end of stream is received from
#       an XMPP server. If it's intentional (XMPP token is in disconnecting
#       state) then do nothing, otherwise disconnect.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In disconnected or disconnecting state none, otherwise ForcedDisconnect
#       procedure is called.

proc ::xmpp::EndOfParse {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""
    CallBack $xlib log input text "</stream:stream>"

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            ForcedDisconnect $xlib
        }
    }

    return
}

# ::xmpp::EndOfFile --
#
#       A callback procedure which is called if an XMPP server has closed
#       connection. If it's intentional (XMPP token is in disconnecting
#       state) then do nothing, otherwise disconnect.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In disconnected or disconnecting state none, otherwise ForcedDisconnect
#       procedure is called.

proc ::xmpp::EndOfFile {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            ForcedDisconnect $xlib
        }
    }

    return
}

# ::xmpp::ForcedDisconnect --
#
#       Disconnect from an XMPP server if this disconnect id forced by the
#       server itself.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In disconnected or disconnecting state none, otherwise this procedure
#       aborts any pending operation, closes the XMPP channel, calls back
#       "disconnect" client function and clears the token state.

proc ::xmpp::ForcedDisconnect {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            set state(status) disconnecting

            if {[info exists state(abortCommand)]} {
                uplevel #0 $state(abortCommand)
                catch {unset state(abortCommand)}
            }

            if {[catch {transport::use $state(transport) close} msg]} {
                Debug $xlib 1 "Closing connection failed: $msg"
            }
            catch {unset state(transport)}

            CallBack $xlib disconnect

            ClearState $xlib
        }
    }

    return
}

# ::xmpp::disconnect --
#
#       Disconnect from an XMPP server.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In disconnected or disconnecting state none, otherwise this procedure
#       aborts any pending operation, closes the XMPP stream and channel, and
#       clears the token state.

proc ::xmpp::disconnect {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    switch -- $state(status) {
        disconnecting -
        disconnected {}
        default {
            set state(status) disconnecting

            if {[info exists state(abortCommand)]} {
                uplevel #0 $state(abortCommand)
                catch {unset state(abortCommand)}
            }

            if {[catch {closeStream $xlib} msg]} {
                Debug $xlib 1 "Closing stream failed: $msg"
            }
            if {[catch {transport::use $state(transport) close} msg]} {
                Debug $xlib 1 "Closing connection failed: $msg"
            }
            catch {unset state(transport)}

            ClearState $xlib
        }
    }
}

# ::xmpp::ClearState --
#
#       Clean XMPP token state.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Empty string.
#
# Side effects:
#       All pending IQ callbacks are called and state array is cleaned up.

proc ::xmpp::ClearState {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    foreach idx [array names state iq,*] {
        set cmd $state($idx)
        unset state($idx)

        uplevel #0 $cmd [list abort \
                              [xml::create error \
                                   -cdata [::msgcat::mc "Disconnected"]]]
    }

    # Don't reset ID counter because the higher level application may
    # still use the old values.
    #set state(id) 0
    set state(status) disconnected

    # connect
    # This variable is unset in [disconnect] or [ForcedDisconnect]
    #array unset state transport

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

    # various
    array unset state abortCommand

    return
}

# ::xmpp::RegisterElement --
#
#       Register callback for XMPP top-level stanza in a stream.
#
# Arguments:
#       xlib            XMPP token.
#       tag             XML element tag pattern.
#       xmlns           XMLNS pattern.
#       cmd             Command to call when the top-level stanza in XMPP
#                       stream matches tag ans XMLNS patterns.
#
# Result:
#       Empty string.
#
# Side effects:
#       Command is pushed to a stack of registered commands for given tag and
#       XMLNS patterns.

proc ::xmpp::RegisterElement {xlib tag xmlns cmd} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$tag $xmlns $cmd"

    lappend state(registered,$tag,$xmlns) $cmd
    return
}

# ::xmpp::UnregisterElement --
#
#       Unregister the last callback for XMPP top-level stanza in a stream.
#
# Arguments:
#       xlib            XMPP token.
#       tag             XML element tag pattern.
#       xmlns           XMLNS pattern.
#
# Result:
#       Empty string. Error is raised if there wasn't a registered command for
#       specified tag ans XMLNS patterns.
#
# Side effects:
#       The last registered command is popped from a stack of registered
#       commands for given tag and XMLNS patterns.

proc ::xmpp::UnregisterElement {xlib tag xmlns} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$tag $xmlns"

    set state(registered,$tag,$xmlns) \
        [lreplace $state(registered,$tag,$xmlns) end end]
    return
}

# ::xmpp::ElementCommand --
#
#       Return the last registerd command for XMPP top-level stanza.
#
# Arguments:
#       xlib            XMPP token.
#       tag             XML element tag.
#       xmlns           XMLNS.
#
# Result:
#       Command which was registered for specified tag and XMLNS if any.
#       Otherwise a command which was registered for patterns which match tag
#       and XMLNS if any. Otherwise an empty string.
#
# Side effects:
#       None.

proc ::xmpp::ElementCommand {xlib tag xmlns} {
    variable $xlib
    upvar 0 $xlib state

    # If there's an exact match, return it
    if {[info exists state(registered,$tag,$xmlns)]} {
        return [lindex $state(registered,$tag,$xmlns) end]
    }

    # Otherwise find matching indices
    foreach idx [lsort [array names state registered,*]] {
        set fields [split $idx ,]
        set ptag [lindex $fields 1]
        set pxmlns [join [lrange $fields 2 end] ,]

        if {[string match $ptag $tag] && [string match $pxmlns $xmlns]} {
            return [lindex $state($idx) end]
        }
    }

    # There's no matches
    return
}

# ::xmpp::Parse --
#
#       A callback procedure which is called when a top-level XMPP stanza is
#       received. It in turn calls a procedure which parses and processes the
#       stanza.
#
# Arguments:
#       xlib            XMPP token
#       xmlElement      Top-level XML stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A registered command for the xmlElement tag and XMLNS is called if any,
#       or general "packet" callback is invoked.

proc ::xmpp::Parse {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$xmlElement"
    CallBack $xlib log input xml $xmlElement

    if {![info exists state(transport)]} {
        Debug $xlib 1 "Connection doesn't exist"
        return -1
    }

    xml::split $xmlElement tag xmlns attrs cdata subels

    set cmd [ElementCommand $xlib $tag $xmlns]
    if {![string equal $cmd ""]} {
        uplevel #0 $cmd [list $xmlElement]
        return
    }

    CallBack $xlib packet $xmlElement
    return
}

# ::xmpp::ParseMessage --
#
#       Parse XMPP message and invoke "message" client callback. The callback
#       must take the following arguments:
#       (Mandatory)
#           xlib                XMPP token.
#           from                From JID.
#           type                Message type ("", "error", "normal", "chat",
#                               "groupchat", "headline").
#           x                   Extra subelements (attachments).
#       (Optional)
#           -x keypairs         Key-valus pairs of extra attributes.
#           -lang lang          xml:lang
#           -to to              To JID (usually own JID).
#           -id id              Stanza ID (string).
#           -subject subject    Message subject (string).
#           -thread thread      Message thread (string).
#           -body body          Message body (string).
#           -error error        Error stanza (XML element).
#
# Arguments:
#       xlib            XMPP token
#       xmlElement      XMPP <message/> stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A message callback is called if defined.

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
            type     {
                switch -- $val {
                    chat -
                    error -
                    groupchat -
                    headline -
                    normal {
                        set type $val
                    }
                    default {
                        Debug $xlib 1 \
                              [::msgcat::mc "Unknown message type %s" $val]
                    }
                }
            }
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

    eval [list CallBack $xlib message $from $type $x -x $xparam] $params
    return
}

# ::xmpp::ParsePresence --
#
#       Parse XMPP presence and invoke "presence" client callback. The callback
#       must take the following arguments:
#       (Mandatory)
#           xlib                XMPP token.
#           from                From JID.
#           type                Presence type ("", "error", "unavailable",
#                               "probe", "subscribe", "subscribed",
#                               "unsubscribe", "unsubscribed").
#           x                   Extra subelements (attachments).
#       (Optional)
#           -x keypairs         Key-valus pairs of extra attributes.
#           -lang lang          xml:lang
#           -to to              To JID (usually own JID).
#           -id id              Stanza ID (string).
#           -priority priority  Presence priority (number).
#           -show show          Presence status (missing, "away", "chat",
#                               "dnd", "xa").
#           -status status      Presence extended status (string).
#           -error error        Error stanza (XML element).
#
# Arguments:
#       xlib            XMPP token
#       xmlElement      XMPP <presence/> stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A presence callback is called if defined.

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

    eval [list CallBack $xlib presence $from $type $x -x $xparam] $params
    return
}

# ::xmpp::ParseIQ --
#
#       Parse XMPP IQ. For get or set IQ type invoke [iq::process] command
#       which will find and invoke the corresponding handler. For result or
#       error IQ type find and call the callback stored in [sendIQ].
#
# Arguments:
#       xlib            XMPP token
#       xmlElement      XMPP <iq/> stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       An IQ handler or the callback specified when IQ was sent is called if
#       defined.

proc ::xmpp::ParseIQ {xlib xmlElement} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 $xmlElement

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
            from {set from $val}
            type {set type $val}
            xml:lang {lappend params -lang $val}
            to {
                set to $val
                lappend params -to $val
            }
            id {
                set id $val
                lappend params -id $val
            }
            default {lappend xparam $key $val}
        }
    }

    # Any IQ.
    eval [list CallBack $xlib iq $from $type $subels -x $xparam] $params

    switch -- $type {
        get -
        set {
            # Registered IQ.
            eval [list iq::process $xlib $from $type \
                                   [lindex $subels 0]] $params
            return
        }
        result {
            if {[info exists state(iq,$id)]} {
                set cmd $state(iq,$id)
                unset state(iq,$id)

                uplevel #0 $cmd [list ok [lindex $subels 0]]
            } else {
                Debug $xlib 1 \
                      [::msgcat::mc "IQ id %s doesn't exist in memory" $id]
            }
            return
        }
        error {
            if {[info exists state(iq,$id)]} {
                set cmd $state(iq,$id)
                unset state(iq,$id)

                set error {}
                foreach subel $subels {
                    xml::split $subel stag sxmlns sattrs scdata ssubels
                    if {[string equal $stag error]} {
                        set error $subel
                        break
                    }
                }

                uplevel #0 $cmd [list error $error]
            } else {
                Debug $xlib 1 \
                      [::msgcat::mc "IQ id %s doesn't exist in memory" $id]
            }
            return
        }
        default {
            Debug $xlib 1 [::msgcat::mc "Unknown IQ type \"%s\"" $type]
            return
        }
    }
}

# ::xmpp::sendMessage --
#
#       Send XMPP message.
#
# Arguments:
#       xlib            XMPP token.
#       to              JID to send message to.
#       -from from      From attribute (it's usually overwritten by server)
#       -type type      Message type ("", "normal", "chat", "groupchat",
#                       "headline", "error").
#       -id id          Stanza ID.
#       -subject subj   Message subject.
#       -thread thread  Message thread.
#       -body body      Message body.
#       -error error    Error stanza.
#       -xlist elements List of attachments.
#
# Result:
#       Length of sent textual representation of message stanza. If negative
#       then the operation is failed.
#
# Side effects:
#       Presence stanza is set to a server.

proc ::xmpp::sendMessage {xlib to args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$to $args"

    if {![info exists state(transport)]} {
        Debug $xlib 1 "Connection doesn't exist"
        return -1
    }

    set attrs(to) $to
    set attrs(xml:lang) [xml::lang]
    set subelements {}

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
    return [outXML $xlib $data]
}

# ::xmpp::sendPresence --
#
#       Send XMPP presence.
#
# Arguments:
#       xlib            XMPP token.
#       -from from      From attribute (it's usually overwritten by server)
#       -to to          JID to send message to.
#       -type type      Presence type (missing, "unavailable", "probe",
#                       "subscribe", "subscribed", "unsubscribe",
#                       "unsubscribed", "error").
#       -id id          Stanza ID.
#       -show show      Presence status (missing, "chat", "away", "xa", "dnd").
#       -status status  Presence extended status.
#       -priority prio  Presence priority (-128 <= prio <= 127).
#       -error error    Error stanza.
#       -xlist elements List of attachments.
#
# Result:
#       Length of sent textual representation of presence stanza. If negative
#       then the operation is failed.
#
# Side effects:
#       Presence stanza is set to a server.

proc ::xmpp::sendPresence {xlib args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$args"

    if {![info exists state(transport)]} {
        Debug $xlib 1 "Connection doesn't exist"
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
    return [outXML $xlib $data]
}

# ::xmpp::sendIQ --
#
#       Send XMPP IQ.
#
# Arguments:
#       xlib            XMPP token.
#       type            IQ type ("get", "set", "result", "error").
#       -from from      From attribute (it's usually overwritten by server)
#       -to to          JID to send message to.
#       -id id          Stanza ID.
#       -command        Command to call when the result IQ will be received.
#                       This option is allowed for "get" and "set" types only.
#       -timeout num    Timeout for waiting an answer (in milliseconds).
#       -query query    Query stanza.
#       -error error    Error stanza.
#
# Result:
#       Id of the sent stanza.
#
# Side effects:
#       IQ stanza is set to a server. If it's a "get" or "set" stanza then
#       depending on -command and -timeout options the command is stored for
#       calling it back later, and the IQ abortion is scheduled.


proc ::xmpp::sendIQ {xlib type args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$type $args"

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

    foreach {key val} $args {
        switch -- $key {
            -from {set attrs(from) $val}
            -to   {
                if {![string equal $val ""]} {
                    set attrs(to) $val
                }
            }
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
                           [::msgcat::mc "Option \"-command\" is illegal for\
                                          IQ type \"%s\"" $attrs(type)]
                }

                # Only the last -command takes effect
                if {![info exists attrs(id)] || ![info exists cmd]} {
                    set attrs(id) [packetID $xlib]
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
        Debug $xlib 1 "Connection doesn't exist"
        if {[info exists cmd]} {
            uplevel #0 $cmd [list abort \
                                  [xml::create error \
                                        -cdata [::msgcat::mc "Disconnected"]]]
        }
        return
    }

    if {[info exists cmd]} {
        set state(iq,$attrs(id)) $cmd
        if {$timeout > 0} {
            after $timeout \
                  [namespace code [list abortIQ $xlib $attrs(id) timeout \
                                [xml::create error \
                                    -cdata [::msgcat::mc "IQ %s timed out" \
                                                         $attrs(id)]]]]
        }
    }

    set data [xml::create iq -attrs [array get attrs] \
                             -subelements $subelements]

    set res [outXML $xlib $data]

    if {[info exists cmd] && $res < 0} {
        after idle \
              [namespace code [list abortIQ $xlib $attrs(id) abort \
                                            [xml::create error \
                                                -cdata [::msgcat::mc \
                                                            "Disconnected"]]]]
    }

    if {$getset && [info exists attrs(id)]} {
        return $attrs(id)
    } else {
        return
    }
}

# ::xmpp::abortIQ --
#
#       Abort a pending IQ request and call its pending command with a
#       specified status.
#
# Arguments:
#       xlib            XMPP token.
#       id              IQ identity attribute.
#       status          "ok", "abort", "timeout", or "error".
#       error           Error XML stanza. (If status is "ok" then error must be
#                       a result stanza).
#
# Result:
#       Empty string.
#
# Side effects:
#       Side effects from the called command.

proc ::xmpp::abortIQ {xlib id status error} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$id"

    if {[info exists state(iq,$id)]} {
        set cmd $state(iq,$id)
        unset state(iq,$id)

        uplevel #0 $cmd [list $status $error]
    } else {
        Debug $xlib 1 [::msgcat::mc "IQ id %s doesn't exist in memory" $id]
    }

    return
}

# ::xmpp::packetID --
#
#       Return the next free packet ID.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Packet ID.
#
# Side effects:
#       The next ID value is increased by one.

proc ::xmpp::packetID {xlib} {
    variable $xlib
    upvar 0 $xlib state

    return [incr state(id)]:[expr {round(rand()*1000000)}]
}

# ::xmpp::CallBack --
#
#       Call a client callback procedure if it was defined in [new].
#
# Arguments:
#       xlib            XMPP token.
#       command         Callback type.
#       args            Arguments for callback.
#
# Result:
#       Callback return code and value:
#
# Side effects:
#       Side effects from the callback.

proc ::xmpp::CallBack {xlib command args} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 "$command"

    set cmd -${command}command

    if {[info exists state($cmd)]} {
        set code [catch {uplevel #0 $state($cmd) [list $xlib] $args} msg]
        return -code $code -errorinfo $::errorInfo $msg
    } else {
        return
    }
}

# ::xmpp::Set --
#
#       Set the specified XMPP token property or get it value.
#
# Arguments:
#       xlib            XMPP token.
#       property        Property to set or get.
#       value           (optional) If present then state variable is set.
#                       If missing then its value is returned.
#
# Result:
#       Value of a corresponding state variable.
#
# Side effects:
#       If value is present then variable state($property) is set.

proc ::xmpp::Set {xlib property args} {
    variable $xlib
    upvar 0 $xlib state

    switch -- [llength $args] {
        0 {
            return $state($property)
        }
        1 {
            return [set state($property) [lindex $args 0]]
        }
        default {
            return -code error \
                   -errorcode [::msgcat::mc "Usage: ::xmpp::Set xlib\
                                             property ?value?"]
        }
    }
}

# ::xmpp::Unset --
#
#       Unset the specified XMPP token property.
#
# Arguments:
#       xlib            XMPP token.
#       property        Property to unset.
#
# Result:
#       Empty string.
#
# Side effects:
#       Variable state($property) is unset.


proc ::xmpp::Unset {xlib property} {
    variable $xlib
    upvar 0 $xlib state

    catch {unset state($property)}
    return
}

# ::xmpp::ip --
#
#       Return IP of low level TCP socket.
#
# Arguments:
#       xlib            XMPP token.
#
# Result:
#       Socket IP or empty string.
#
# Side effects:
#       None.

proc ::xmpp::ip {xlib} {
    variable $xlib
    upvar 0 $xlib state

    Debug $xlib 2 ""

    return [transport::use $state(transport) ip]
}

# ::xmpp::Debug --
#
#       Prints debug information.
#
# Arguments:
#       xlib    XMPP token.
#       level   A debug level.
#       str     A debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::xmpp::debug variable is not less than num.

proc ::xmpp::Debug {xlib level str} {
    variable debug

    if {$debug >= $level} {
        puts "[clock format [clock seconds] -format %T]\
              [lindex [info level -1] 0] $xlib $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
