# compress.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       compressed jabber stream.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::stanzaerror 0.1
package require xmpp::transport::zlib 0.1

package provide xmpp::compress 0.1

namespace eval ::xmpp::compress {
    variable SupportedMethods {zlib}

    foreach {lcode type cond description} [list \
        409 modify setup-failed       [::msgcat::mc "Compression setup\
                                                     failed"] \
        409 modify unsupported-method [::msgcat::mc "Unsupported compression\
                                                     method"]] \
    {
        ::xmpp::stanzaerror::registerError $lcode $type $cond $description
    }
}

##########################################################################

proc ::xmpp::compress::compress {xlib args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::Set $xlib abortCommand [namespace code [abort $token]]

    set state(xlib) $xlib
    set timeout 0

    foreach {key val} $args {
        switch -- $key {
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            default {
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    ::xmpp::RegisterElement $xlib * http://jabber.org/protocol/compress \
                            [namespace code [list Parse $token]]

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortCompression $token timeout \
                                    [::msgcat::mc "Compression timed out"]]]]
    }

    ::xmpp::TraceStreamFeatures $xlib \
                        [namespace code [list Continue $token]]

    if {[info exists state(-command)]} {
        # Asynchronous mode
        return $token
    } else {
        # Synchronous mode
        vwait $token\(status)

        set status $state(status)
        set msg $state(msg)
        unset state

        if {[string equal $status ok]} {
            return $msg
        } else {
            if {[string equal $status abort]} {
                return -code break $msg
            } else {
                return -code error $msg
            }
        }
    }
}

# ::xmpp::compress::abort --
#
#       Abort an existing compression procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Compression control token which is returned by
#                       ::xmpp::compress::compress procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::compress::abort {token} {
    AbortCompression $token abort [::msgcat::mc "Compression aborted"]
}

# ::xmpp::compress::AbortCompression --
#
#       Abort an existing compression procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Compression control token which is returned by
#                       ::xmpp::compress::compress procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::compress::AbortCompression {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    if {[info exists state(reopenStream)]} {
        ::xmpp::GotStream $xlib abort {}
        return
    }

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                [namespace code [list Continue $token]]

    Finish $token $status [::xmpp::xml::create error -cdata $msg]
}

##########################################################################

proc ::xmpp::compress::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        compressed {
            Compressed $token
        }
        failure {
            Failure $token $subels
        }
    }
}

##########################################################################

proc ::xmpp::compress::Continue {token featuresList} {
    variable SupportedMethods
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $featuresList"

    if {[catch {FindMethods $featuresList} methods]} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable -text \
                        [::msgcat::mc "Server hasn't provided\
                                       compress feature"]]
        return
    }

    ::xmpp::Debug $xlib 2 "$token methods: $methods"

    foreach m $SupportedMethods {
        if {[lsearch -exact $methods $m] >= 0} {
            set method $m
            break
        }
        if {![info exists method]} {
            Finish $token error \
                   [::xmpp::stanzaerror::error modify not-acceptable \
                         -text [::msgcat::mc \
                                    "Server hasn't provided supported\
                                     compress method"]]
            return
        }
    }

    set state(method) $method

    set data [::xmpp::xml::create compress \
                  -xmlns http://jabber.org/protocol/compress \
                  -subelement [::xmpp::xml::create method -cdata $method]]

    ::xmpp::outXML $xlib $data
}

proc ::xmpp::compress::FindMethods {featuresList} {
    set compressFeature 0
    set methods {}

    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        if {[string equal $xmlns http://jabber.org/features/compress] && \
                [string equal $tag compression]} {
            set compressFeature 1
            set methods {}
            foreach subel $subels {
                ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
                if {[string equal $stag method]} {
                    lappend methods $scdata
                }
            }
        }
    }

    if {$compressFeature} {
        return $methods
    } else {
        return -code error
    }
}

##########################################################################

proc ::xmpp::compress::Failure {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set error [lindex $xmlElements 0]
    if {[string equal $error ""]} {
        set err [::xmpp::stanzaerror::error modify undefined-condition \
                     -text [::msgcat::mc "Compression negotiation failed"]]
    } else {
        ::xmpp::xml::split $error tag xmlns attrs cdata subels
        set err [::xmpp::stanzaerror::error modify $tag]
    }
    Finish $token error $err
}

##########################################################################

proc ::xmpp::compress::Compressed {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::SwitchTransport $xlib $state(method)

    set state(reopenStream) \
        [::xmpp::ReopenStream $xlib \
                              -command [namespace code [list Reopened $token]]]
    return
}

proc ::xmpp::compress::Reopened {token status sessionid} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    unset state(reopenStream)

    ::xmpp::Debug $xlib 2 "$token $status $sessionid"

    if {[string equal $status $ok]} {
        Finish $token ok {}
    } else {
        Finish $token $status [::xmpp::xml::create error -cdata $sessionid]
    }
}

##########################################################################

proc ::xmpp::compress::Finish {token status xmlData} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    ::xmpp::UnregisterElement $xlib * http://jabber.org/protocol/compress

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    ::xmpp::Debug $xlib 2 "$token $status"

    if {[string equal $status ok]} {
        set msg ""
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Compression negotiation successful"]
    } else {
        set msg [::xmpp::stanzaerror::message $xmlData]
        ::xmpp::CallBack $xlib status \
                         [::msgcat::mc "Compression negotiation failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        set state(msg) $msg
        # Trigger vwait in [compress]
        set state(status) $status
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
