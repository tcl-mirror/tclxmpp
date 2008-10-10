# sasl.tcl --
#
#       This file is part of the XMPP library. It provides support for the
#       SASL authentication layer via the tclsasl or tcllib SASL package.
#       Also, it binds resource and opens XMPP session.
#
# Copyright (c) 2008 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require base64
package require xmpp::stanzaerror

package provide xmpp::sasl 0.1

namespace eval ::xmpp::sasl {
    namespace export auth abort

    variable saslpack

    if {![catch {package require sasl 1.0}]} {
        set saslpack tclsasl
    } elseif {![catch {package require SASL 1.0}]} {
        catch {package require SASL::NTLM}
        catch {package require SASL::XGoogleToken}
        set saslpack tcllib
    } else {
        return -code error -errorinfo [::msgcat::mc "No SASL package found"]
    }

    switch -- $saslpack {
        tclsasl {
            sasl::client_init -callbacks {}
        }
        default {
            # empty
        }
    }

    # SASL error messages
    ::xmpp::stanzaerror::registerType sasl [::msgcat::mc "Authentication Error"]

    foreach {lcode type cond description} [list \
        401 sasl aborted                [::msgcat::mc "Aborted"] \
        401 sasl incorrect-encoding     [::msgcat::mc "Incorrect encoding"] \
        401 sasl invalid-authzid        [::msgcat::mc "Invalid authzid"] \
        401 sasl invalid-mechanism      [::msgcat::mc "Invalid mechanism"] \
        401 sasl mechanism-too-weak     [::msgcat::mc "Mechanism too weak"] \
        401 sasl not-authorized         [::msgcat::mc "Not Authorized"] \
        401 sasl temporary-auth-failure [::msgcat::mc "Temporary auth\
                                                       failure"]] \
    {
        ::xmpp::stanzaerror::registerError $lcode $type $cond $description
    }
}

##########################################################################

proc ::xmpp::sasl::auth {xlib args} {
    variable saslpack
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    ::xmpp::Debug $xlib 2 $token

    ::xmpp::Set $xlib abortCommand [namespace code [abort $token]]

    set state(xlib) $xlib
    set state(-server)  [::xmpp::Set $xlib server]
    set state(-digest)  1
    set state(-disable) {}
    set timeout 0
    catch {unset state(mechanisms)}

    foreach {key val} $args {
        switch -- $key {
            -domain   -
            -secret   -
            -username -
            -resource -
            -password -
            -disable  -
            -command {
                set state($key) $val
            }
            -timeout {
                set timeout $val
            }
            -digest {
                if {[string is true -strict $val]} {
                    set state(-digest) 1
                } elseif {[string is false -strict $val]} {
                    set state(-digest) 0
                } elseif {[string equal $val auto]} {
                    set state(-digest) 0.5
                } else {
                    unset state
                    return -code error \
                           -errorinfo [::msgcat::mc \
                                           "Illegal value \"%s\" for\
                                            option \"%s\"" $val $key]
                }
            }
            default {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Illegal option \"%s\"" $key]
            }
        }
    }

    set count 0
    foreach key {-username -domain} {
        if {[info exists state($key)]} {
            incr count
        }
    }
    if {$count >= 2} {
        unset state
        return -code error \
               -errorinfo [::msgcat::mc "Only one option \"-username\"\
                                         or \"-domain\" is allowed"]
    }

    if {[info exists state(-username)]} {
        foreach key {-resource
                     -password} {
            if {![info exists state($key)]} {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Missing option \"%s\"" $key]
            }
        }
    } elseif {[info exists state(-domain)]} {
        foreach key {-secret} {
            if {![info exists state($key)]} {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Missing option \"%s\"" $key]
            }
        }
    } else {
        unset state
        return -code error \
               -errorinfo [::msgcat::mc "Missing option \"-username\"\
                                         or \"-domain\""]
    }

    ::xmpp::RegisterElement $xlib * urn:ietf:params:xml:ns:xmpp-sasl \
                            [namespace code [list Parse $token]]

    # Resource binding and session establishing use IQ
    ::xmpp::RegisterElement $xlib iq * [list ::xmpp::ParseIQ $xlib]

    switch -- $saslpack {
        tclsasl {
            foreach id {authname pass getrealm cnonce} {
                lappend callbacks \
                    [list $id [namespace code [list TclsaslCallback $token]]]
            }

            set state(token) \
                [sasl::client_new -service     xmpp \
                                  -serverFQDN  $state(-server) \
                                  -callbacks   $callbacks \
                                  -flags       success_data]

            if {$state(-digest) == 1} {
                set flags {noplaintext}
            } elseif {$state(-digest) > 0} {
                set flags {}
            } else {
                unset state
                return -code error \
                       -errorinfo [::msgcat::mc "Cannot forbid digest\
                                                 mechanisms"]
            }

            $state(token) -operation setprop \
                          -property sec_props \
                          -value [list min_ssf 0 \
                                       max_ssf 0 \
                                       flags $flags]
        }
        tcllib {
            set state(token) \
                [SASL::new -service xmpp \
                           -type client \
                           -server $state(-server) \
                           -callback [namespace code [list TcllibCallback \
                                                           $token]]]
            # Workaround a bug 1545306 in Tcllib SASL module
            set ::SASL::digest_md5_noncecount 0
        }
    }

    if {$timeout > 0} {
        set state(afterid) \
            [after $timeout \
                   [namespace code \
                              [list AbortAuth $token timeout \
                                    [::msgcat::mc "SASL authentication\
                                                   timed out"]]]]
    }

    ::xmpp::TraceStreamFeatures $xlib \
                    [namespace code [list AuthContinue $token]]

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

# ::xmpp::sasl::abort --
#
#       Abort an existing authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::sasl::auth procedure.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::sasl::abort {token} {
    AbortAuth $token abort [::msgcat::mc "SASL authentication aborted"]
}

# ::xmpp::sasl::AbortAuth --
#
#       Abort an existing authentication procedure, or do nothing if it's
#       already finished.
#
# Arguments:
#       token           Authentication control token which is returned by
#                       ::xmpp::sasl::auth procedure.
#       status          (error, abort or timeout) Status code of the abortion.
#       msg             Error message.
#
# Result:
#       Empty string.
#
# Side effects:
#       In state of waiting for reply from server terminates waiting process.

proc ::xmpp::sasl::AbortAuth {token status msg} {
    variable $token
    upvar 0 $token state

    if {![info exists state(xlib)]} return

    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    ::xmpp::RemoveTraceStreamFeatures $xlib \
                                [namespace code [list AuthContinue $token]]

    if {[info exists state(reopenStream)]} {
        ::xmpp::GotStream $xlib abort {}
        return
    }

    set error [::xmpp::xml::create error -cdata $msg]

    if {[info exists state(id)]} {
        ::xmpp::abortIQ $xlib $state(id) $status $error
    } else {
        Finish $token $status $error
    }
    return
}

##########################################################################

proc ::xmpp::sasl::Parse {token xmlElement} {
    variable $token
    upvar 0 $token state

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    switch -- $tag {
        challenge {
            Step $token $cdata
        }
        success {
            Success $token
        }
        failure {
            Failure $token $subels
        }
    }
}

##########################################################################

proc ::xmpp::sasl::AuthContinue {token featuresList} {
    variable saslpack
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $featuresList"

    if {[catch {FindMechanisms $featuresList} mechanisms]} {
        Finish $token error \
               [::xmpp::stanzaerror::error modify not-acceptable -text \
                        [::msgcat::mc "Server hasn't provided SASL\
                                       authentication feature"]]
        return
    }

    ::xmpp::Debug $xlib 2 "$token mechs: $mechanisms"

    switch -- $saslpack {
        tclsasl {
            set code [catch {
                $state(token) \
                    -operation start \
                    -mechanisms $mechanisms \
                    -interact [namespace code [list Interact $token]]
            } result]
        }
        tcllib {
            set code [catch {ChooseMech $token $mechanisms} result]

            if {!$code} {
                set mech $result
                SASL::configure $state(token) -mech $mech
                switch -- $mech {
                    PLAIN -
                    X-GOOGLE-TOKEN {
                        # Initial responce
                        set code [catch {SASL::step $state(token) ""} result]
                        if {!$code} {
                            set output [SASL::response $state(token)]
                        }
                    }
                    default {
                        set output ""
                    }
                }
                if {!$code} {
                    set result [list mechanism $mech output $output]
                }
            }
        }
    }

    ::xmpp::Debug $xlib 2 "$token SASL code $code: $result"

    switch -- $code {
        0 -
        4 {
            array set resarray $result
            set data [::xmpp::xml::create auth \
                          -xmlns urn:ietf:params:xml:ns:xmpp-sasl \
                          -attrs [list mechanism $resarray(mechanism)] \
                          -cdata [base64::encode -maxlen 0 $resarray(output)]]

            ::xmpp::outXML $xlib $data
        }
        default {
            set str [::msgcat::mc "SASL auth error:\n%s" $result]
            Finish $token error \
                   [::xmpp::stanzaerror::error sasl undefined-condition \
                            -text $str]
        }
    }
}

proc ::xmpp::sasl::FindMechanisms {featuresList} {
    set saslFeature 0
    set mechanisms {}

    foreach feature $featuresList {
        ::xmpp::xml::split $feature tag xmlns attrs cdata subels

        if {[string equal $xmlns urn:ietf:params:xml:ns:xmpp-sasl] && \
                [string equal $tag mechanisms]} {
            set saslFeature 1
            foreach subel $subels {
                ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels
                if {[string equal $stag mechanism]} {
                    lappend mechanisms $scdata
                }
            }
        }
    }

    if {$saslFeature} {
        return $mechanisms
    } else {
        return -code error
    }
}

##########################################################################

proc ::xmpp::sasl::ChooseMech {token mechanisms} {
    variable $token
    upvar 0 $token state

    set forbiddenMechs $state(-disabled)

    if {$state(-digest) = 1} {
        lappend forbiddenMechs PLAIN LOGIN
    } elseif {$state(-digest) == 0} {
        foreach m [SASL::mechanisms] {
            switch -- $m {
                PLAIN -
                LOGIN {}
                default {lappend forbiddenMechs $m}
            }
        }
    }

    foreach m [SASL::mechanisms] {
        if {[lsearch -exact $mechanisms $m] >= 0 && \
                [lsearch -exact $forbidden_mechs $m] < 0} {
            return $m
        }
    }
    if {[llength $mechanisms] == 0} {
        return -code error [::msgcat::mc "Server provided no SASL mechanisms"]
    } elseif {[llength $mechanisms] == 1} {
        return -code error [::msgcat::mc "Server provided mechanism\
                                          %s. It is forbidden" \
                                         [lindex $mechanisms 0]]
    } else {
        return -code error [::msgcat::mc "Server provided mechanisms\
                                          %s. They are forbidden" \
                                         [join $mechanisms ", "]]
    }
}

##########################################################################

proc ::xmpp::sasl::Step {token serverin64} {
    variable saslpack
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    set serverin [base64::decode $serverin64]

    switch -- $saslpack {
        tclsasl {
            set code [catch {
                $state(token) \
                    -operation step \
                    -input     $serverin \
                    -interact  [namespace code [list Interact $token]]
            } result]
        }
        tcllib {
            set code [catch {SASL::step $state(token) $serverin} result]

            if {!$code} {
                set result [SASL::response $state(token)]
            }
        }
    }

    ::xmpp::Debug $xlib 2 "$token SASL code $code: $result"

    switch -- $code {
        0 -
        4 {
            set data [::xmpp::xml::create response \
                          -xmlns urn:ietf:params:xml:ns:xmpp-sasl \
                          -cdata [base64::encode -maxlen 0 $result]]

            ::xmpp::outXML $xlib $data
        }
        default {
            Finish $token error \
                   [::xmpp::stanzaerror::error sasl undefined-condition \
                            -text [::msgcat::mc "SASL step error: %s" $result]]
        }
    }
}

##########################################################################

proc ::xmpp::sasl::TclsaslCallback {token data} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $data"

    array set params $data

    switch -- $params(id) {
        user {
            # authzid
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 \
                                 $state(-username)@$state(-server)]
            } else {
                return [encoding convertto utf-8 $state(-domain)]
            }
        }
        authname {
            #username
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 $state(-username)]
            } else {
                return [encoding convertto utf-8 $state(-domain)]
            }
        }
        pass {
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 $state(-password)]
            } else {
                return [encoding convertto utf-8 $state(-secret)]
            }
        }
        getrealm {
            return [encoding convertto utf-8 $state(-server)]
        }
        default {
            return -code error \
                [::msgcat::mc "SASL callback error: client needs to\
                               write \"%s\"" $params(id)]
        }
    }
}

##########################################################################

proc ::xmpp::sasl::TcllibCallback {token stoken command args} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $stoken $command"

    switch -- $command {
        login {
            # authzid
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 \
                                 $state(-username)@$state(-server)]
            } else {
                return [encoding convertto utf-8 $state(-domain)]
            }
        }
        username {
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 $state(-username)]
            } else {
                return [encoding convertto utf-8 $state(-domain)]
            }
        }
        password {
            if {[info exists state(-username)]} {
                return [encoding convertto utf-8 $state(-password)]
            } else {
                return [encoding convertto utf-8 $state(-secret)]
            }
        }
        realm {
            return [encoding convertto utf-8 $state(-server)]
        }
        hostname {
            return [info host]
        }
        default {
            return -code error \
                [::msgcat::mc "SASL callback error: client needs to\
                               write \"%s\"" $command]
        }
    }
}

##########################################################################

proc ::xmpp::sasl::Interact {token data} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token $data"
    # empty
}

##########################################################################

proc ::xmpp::sasl::Failure {token xmlElements} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    set error [lindex $xmlElements 0]
    if {$error == ""} {
        set err not-authorized
    } else {
        ::xmpp::xml::split $error tag xmlns attrs cdata subels
        set err $tag
    }
    Finish $token error [::xmpp::stanzaerror::error sasl $err]
}

##########################################################################

proc ::xmpp::sasl::Success {token} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$token"

    # XMPP core section 6.2:
    # Upon receiving the <success/> element,
    # the initiating entity MUST initiate a new stream by sending an
    # opening XML stream header to the receiving entity (it is not
    # necessary to send a closing </stream> tag first...
    # Moreover, some servers (ejabberd) won't work if stream is closed.

    set state(reopenStream) \
        [::xmpp::ReopenStream $xlib \
                              -command [namespace code [list Reopened $token]]]
    return
}

##########################################################################

proc ::xmpp::sasl::Reopened {token status sessionid} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    unset state(reopenStream)

    ::xmpp::Debug $xlib 2 "$token $status $sessionid"

    if {![string equal $status ok]} {
        Finish $token $status [::xmpp::xml::create error -cdata $sessionid]
        return
    }

    ::xmpp::TraceStreamFeatures $xlib \
                    [namespace code [list ResourceBind $token]]
    return
}

##########################################################################

proc ::xmpp::sasl::ResourceBind {token featuresList} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    if {[info exists state(-username)]} {
        foreach feature $featuresList {
            ::xmpp::xml::split $feature tag xmlns attrs cdata subels

            if {[string equal $xmlns urn:ietf:params:xml:ns:xmpp-bind] && \
                    [string equal $tag bind]} {
                if {[string equal $state(-resource) ""]} {
                    set subelements {}
                } else {
                    set subelements [list [::xmpp::xml::create resource \
                                                    -cdata $state(-resource)]]
                }

                set data [::xmpp::xml::create bind \
                                    -xmlns $xmlns \
                                    -subelements $subelements]

                set state(id) \
                    [::xmpp::sendIQ $xlib set \
                            -query $data \
                            -command [namespace code [list SendSession $token]]]
                return
            }
        }

        Finish $token abort "Can't bind resource"
        return
    } else {
        foreach feature $featuresList {
            ::xmpp::xml::split $feature tag xmlns attrs cdata subels

            if {[string equal $xmlns urn:xmpp:component] && \
                    [string equal $tag bind]} {
                set subelements [list [::xmpp::xml::create hostname \
                                                -cdata $state(-domain)]]

                set data [::xmpp::xml::create bind \
                                    -xmlns $xmlns \
                                    -subelements $subelements]

                set state(id) \
                    [::xmpp::sendIQ $xlib set \
                            -query $data \
                            -command [namespace code [list Finish $token]]]
                return
            }
        }

        Finish $token abort "Can't bind hostname"
        return
    }
}

##########################################################################

proc ::xmpp::sasl::SendSession {token status xmlData} {
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    ::xmpp::Debug $xlib 2 "$xmlData"

    switch -- $status {
        ok {
            # Store returned JID
            ::xmpp::xml::split $xmlData tag xmlns attrs cdata subels
            foreach subel $subels {
                ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

                switch -- $stag {
                    jid {
                        set state(jid) $scdata
                    }
                }
            }
            # Establish the session.
            set data [::xmpp::xml::create session \
                              -xmlns urn:ietf:params:xml:ns:xmpp-session]

            set state(id) \
                [::xmpp::sendIQ $xlib set \
                        -query $data \
                        -command [namespace code [list Finish $token]]]
        }
        default {
            Finish $token $status $xmlData
        }
    }
}

##########################################################################

proc ::xmpp::sasl::Finish {token status xmlData} {
    variable saslpack
    variable $token
    upvar 0 $token state
    set xlib $state(xlib)

    if {[info exists state(afterid)]} {
        after cancel $state(afterid)
    }

    ::xmpp::Unset $xlib abortCommand

    if {[info exists state(jid)]} {
        set jid $state(jid)
    } elseif {[info exists state(-username)]} {
        set jid [::xmpp::jid::jid $state(-username) \
                                  $state(-server) \
                                  $state(-resource)]
    } else {
        set jid $state(-domain)
    }

    ::xmpp::Debug $xlib 2 "$status"

    ::xmpp::UnregisterElement $xlib * urn:ietf:params:xml:ns:xmpp-sasl
    ::xmpp::UnregisterElement $xlib iq *

    if {[info exists state(token)]} {
        switch -- $saslpack {
            tclsasl {
                rename $state(token) ""
            }
            tcllib {
                SASL::cleanup $state(token)
            }
        }
    }

    # Cleanup in asynchronous mode
    if {[info exists state(-command)]} {
        set cmd $state(-command)
        unset state
    }

    if {[string equal $status ok]} {
        set msg $jid
        ::xmpp::CallBack $xlib status [::msgcat::mc "Authentication succeeded"]
    } else {
        set msg [::xmpp::stanzaerror::message $xmlData]
        ::xmpp::CallBack $xlib status [::msgcat::mc "Authentication failed"]
    }

    if {[info exists cmd]} {
        # Asynchronous mode
        uplevel #0 $cmd [list $status $msg]
    } else {
        # Synchronous mode
        set state(msg) $msg
        # Trigger vwait in [auth]
        set state(status) $status
    }
    return
}

# vim:ts=8:sw=4:sts=4:et
