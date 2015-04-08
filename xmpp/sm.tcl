# sm.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       Stream Management (XEP-0198) protocol.
#
# Copyright (c) 2015 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.

package require xmpp::stanzaerror

package provide xmpp::sm 0.1

namespace eval ::xmpp::sm {}

# ::xmpp::sm::new --
#
# Arguments:
#       xlib                    XMPP token. It must be connected and XMPP
#                               stream must be opened.
#
# Result:
#       A control token is returned.
#
# Side effects:
#       A variable in ::xmpp::sm namespace is created and stream management
#       state is stored in it.

proc ::xmpp::sm::new {xlib} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    ::xmpp::Debug $xlib 2 "$token"

    set state(xlib) $xlib
    reset $token

    ::xmpp::RegisterElement $xlib * urn:xmpp:sm:3 \
                            [namespace code [list Parse $token]]
    return $token
}

proc ::xmpp::sm::reset {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set state(count-in) 0   ; # Number of received stanzas
    set state(count-out) 0  ; # Number of acknowledged sent stanzas
    set state(queue) {}     ; # Queue of unacknowledged yet sent stanzas
    set state(location) ""  ; # Preferred resume location
    set state(id) ""        ; # Stream ID for resumption
    set state(resume) 0     ; # Whether the server agree to resume the stream
    set state(max) 0        ; # Maximum resumption time (0 for infinity)
    set state(enabled) 0    ; # Whether the SM is enabled

    return
}

proc ::xmpp::sm::free {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::UnregisterElement $xlib * urn:xmpp:sm:3

    array unset state
    return
}

# ::xmpp::sm::enable --
#
#       Enable stream management for the specified connection.
#
# Arguments:
#       token                   SM token. The associated with it XMPP
#                               stream must be opened and authenticated.
#       -command    callback    After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and empty string if
#                               status is "ok", or error stanza otherwise.
#       -resume     boolean     (optional, defaults to false) Whether to enable
#                               stream resumption.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for stream management
#                               negotiation.
#
# Result:
#       Empty string.
#
# Side effects:
#       A continuation procedure is scheduled.

proc ::xmpp::sm::enable {token args} {
    eval [list EnableResume $token enable] $args
}

# ::xmpp::sm::resume --
#
#       Resume XMPP stream using the stream management protocol for the
#       specified connection.
#
# Arguments:
#       token                   SM token. The associated with it XMPP
#                               stream must be opened and authenticated.
#       -command    callback    After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and empty string if
#                               status is "ok", or error stanza otherwise.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for stream management
#                               negotiation.
#
# Result:
#       Empty string.
#
# Side effects:
#       A continuation procedure is scheduled.

proc ::xmpp::sm::resume {token args} {
    eval [list EnableResume $token resume] $args
}

# ::xmpp::sm::EnableResume --
#
#       Enable or resume stream management for the specified connection.
#
# Arguments:
#       token                   SM token. The associated with it XMPP
#                               stream must be opened and authenticated.
#       -command    callback    After successful or failed authentication
#                               "callback" is invoked with two appended
#                               arguments: status ("ok", "error", "abort" or
#                               "timeout") and empty string if
#                               status is "ok", or error stanza otherwise.
#       -resume     boolean     (optional, makes sense for enabling only,
#                               defaults to false) Whether to enable
#                               stream resumption.
#       -timeout    timeout     (optional, defaults to 0 which means infinity)
#                               Timeout (in milliseconds) for stream management
#                               negotiation.
#
# Result:
#       Empty string.
#
# Side effects:
#       A continuation procedure is scheduled.


proc ::xmpp::sm::EnableResume {token mode args} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::Set $xlib abortCommand [namespace code [list abort $token]]

    set state(mode) $mode
    catch {unset state(-command)}
    if {[string equal $mode enable]} {
        set state(-resume) 0
    }
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -resume {
                if {[string equal $mode enable]} {
                    set state(-resume) [string is true $val]
                }
            }
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            default {
                return -code error [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    if {![info exists state(-command)]} {
        return -code error [::msgcat::mc "Option -command is mandatory"]
    }

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortEnable $token timeout \
                                    [::msgcat::mc "Stream management\
                                                   negotiation timed out"]]]]
    }

    ::xmpp::TraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    return
}

# ::xmpp::sm::abort --
#
#       Abort an existing stream management negotiation procedure, or do
#       nothing if it's already finished.
#
# Arguments:
#       token           SM token.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::sm::abort {token} {
    variable $token
    upvar 0 $token state
    AbortEnable $token abort [::msgcat::mc "Stream management\
                                            negotiation aborted"]
}

# ::xmpp::sm::AbortEnable --
#
#       Abort an existing stream management negotiation procedure, or do
#       nothing if it's already finished.
#
# Arguments:
#       token           Stream management control token which is returned by
#                       ::xmpp::sm::new procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::sm::AbortEnable {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    Finish $token $status [::xmpp::xml::create error -cdata $msg]
}

# ::xmpp::sm::Continue --
#
#       A helper procedure which checks if there is a stream management feature
#       in a features list provided by server and continues or finishes the
#       negotiation.
#
# Arguments:
#       token           SM control token.
#       featuresList    XMPP features list from server.
#
# Result:
#       Empty string.
#
# Side effects:
#       Either a SM request is sent to server or negotiation is
#       finished with error.

proc ::xmpp::sm::Continue {token featuresList} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set smFeature 0
    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        switch -- $tag/$xmlns {
            sm/urn:xmpp:sm:3 {
                set smFeature 1
                break
            }
        }
    }

    if {!$smFeature} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable -text \
                     [::msgcat::mc "Server hasn't provided stream management feature"]]
        return
    }

    if {[string equal $state(mode) enable]} {
        set state(count-in) 0
        set state(count-out) 0
        set state(queue) {}
        set state(location) ""
        set state(id) ""
        set state(max) 0
        set state(resume) 0
        set state(enabled) 0

        set attrs {}
        if {$state(-resume)} {
            lappend attrs resume true
        }
        ::xmpp::outXML $xlib [::xmpp::xml::create enable \
                                        -xmlns urn:xmpp:sm:3 \
                                        -attrs $attrs]
    } else {
        set state(enabled) 0

        if {!$state(resume)} {
            Finish $token error \
                   [::xmpp::stanzaerror::error cancel item-not-found]
            return
        }

        ::xmpp::outXML $xlib [::xmpp::xml::create resume \
                                        -xmlns urn:xmpp:sm:3 \
                                        -attrs [list h      $state(count-in) \
                                                     previd $state(id)]]
    }
}

# ::xmpp::sm::Parse --
#
#       Parse XML elemens in urn:xmpp:sm:3 namespace. They
#       indicate the result of negotiation procedure (success or failure).
#
# Arguments:
#       token           SM control token.
#       xmlElement      Top-level XML stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A corresponding procedure is called in cases of successful or failed
#       sm negotiation.

proc ::xmpp::sm::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        enabled {
            set state(enabled) 1
            foreach {attr val} $attrs {
                switch -- $attr {
                    id -
                    max -
                    location {
                        set state($attr) $val
                    }
                    resume {
                        set state(resume) [string is true $val]
                    }
                }
            }
            Finish $token ok $xmlElement
        }
        resumed {
            set state(enabled) 1
            foreach {attr val} $attrs {
                switch -- $attr {
                    h {
                        set qc [PullFromQueue $xlib \
                                              $state(queue) \
                                              $state(count-out) \
                                              $val]
                        set state(queue) [lindex $qc 0]
                        set state(count-out) [lindex $qc 1]
                    }
                    previd {
                        # TODO: Check if IDs match
                        set state(id) $val
                    }
                }
            }
            Finish $token ok $xmlElement
        }
        failed {
            set state(enabled) 0
            Failed $token $subels
        }
        a {
            set qc [PullFromQueue $xlib \
                                  $state(queue) \
                                  $state(count-out) \
                                  [::xmpp::xml::getAttr $attrs h]]
            set state(queue) [lindex $qc 0]
            set state(count-out) [lindex $qc 1]
        }
        r {
            ::xmpp::outXML $xlib \
                           [::xmpp::xml::create a \
                                    -xmlns urn:xmpp:sm:3 \
                                    -attrs [list h $state(count-in)]]
        }
    }
}

proc ::xmpp::sm::PullFromQueue {xlib queue countold countnew} {
    set countnew [expr {$countnew % (1<<32)}]
    if {$countnew < $countold} {
        set countold [expr {$countold - (1<<32)}]
    }
    for {set i $countold} {$i < $countnew} {incr i} {
        set xmlElement [lindex $queue 0]
        ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels
        set id [::xmpp::xml::getAttr $attrs id]
        if {[string equal $tag message] && ![string equal $id ""]} {
            # TODO: Should we call back for presence and IQ as well?
            ::xmpp::CallBack $xlib sm ack $id
        }
        set queue [lreplace $queue 0 0]
    }
    list $queue $countnew
}

proc ::xmpp::sm::count {token mode xmlElement} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    if {!$state(enabled)} return

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        iq -
        presence -
        message {
            if {[string equal $mode in]} {
                set state(count-in) [expr {($state(count-in) + 1) % (1<<32)}]
            } else {
                # TODO: Add a delay subelement
                lappend state(queue) $xmlElement
                ::xmpp::outXML $xlib [::xmpp::xml::create r \
                                              -xmlns urn:xmpp:sm:3]
            }
        }
    }
}

# ::xmpp::sm::Failed --
#
#       A helper procedure which is called if SM negotiations failed. It
#       finishes SM procedure with error.
#
# Arguments:
#       token           SM control token.
#       xmlElements     Subelements of <failure/> element which include error.
#
# Result:
#       Empty string.
#
# Side effects:
#       SM negotiation is finished with error.

proc ::xmpp::sm::Failed {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set error [lindex $xmlElements 0]
    if {[string equal $error ""]} {
        set err [::xmpp::stanzaerror::error modify undefined-condition \
                        -text [::msgcat::mc "Stream management negotiation failed"]]
    } else {
        ::xmpp::xml::split $error tag xmlns attrs cdata subels
        set err [::xmpp::stanzaerror::error modify $tag]
    }
    Finish $token error $err
}

# ::xmpp::sm::Finish --
#
#       A hepler procedure which finishes negotiation process.
#
# Arguments:
#       token           SM control token.
#       status          Status of the negotiations ("ok" means success).
#       xmlData         Either a returned enabled stanza if status is ok or
#                       error stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       A callback is called.

proc ::xmpp::sm::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
        unset state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    ::xmpp::Debug $xlib 2 "$token $status"

    if {[string equal $status ok]} {
        ::xmpp::CallBack $xlib status [::msgcat::mc "Stream management negotiation successful"]
    } else {
        ::xmpp::CallBack $xlib status [::msgcat::mc "Stream management negotiation failed"]
    }

    if {[info exists state(-command)]} {
        uplevel #0 $state(-command) [list $status $xmlData]
        unset state(-command)
    }
}

# vim:ts=8:sw=4:sts=4:et
