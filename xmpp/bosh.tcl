# bosh.tcl --
#
#       This file is a part of the XMPP library. It implements XMPP over BOSH
#       (XEP-0124 and XEP-0206).
#
# Copyright (c) 2013 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require sha1
package require http

package require xmpp::transport 0.2
package require xmpp::xml

package provide xmpp::transport::bosh 0.2

namespace eval ::xmpp::transport::bosh {
    namespace export open abort close reset flush ip outXML outText \
                     openStream reopenStream closeStream

    ::xmpp::transport::register bosh \
            -opencommand         [namespace code open]         \
            -abortcommand        [namespace code abort]        \
            -closecommand        [namespace code close]        \
            -resetcommand        [namespace code reset]        \
            -flushcommand        [namespace code flush]        \
            -ipcommand           [namespace code ip]           \
            -outxmlcommand       [namespace code outXML]       \
            -outtextcommand      [namespace code outText]      \
            -openstreamcommand   [namespace code openStream]   \
            -reopenstreamcommand [namespace code reopenStream] \
            -closestreamcommand  [namespace code closeStream]

    if {![catch { package require tls 1.4 }]} {
        ::http::register https 443 ::tls::socket
    }

    # Supported BOSH version
    variable ver 1.10

    # Namespaces used in BOSH and XMPP over BOSH
    variable NS
    array set NS {bind http://jabber.org/protocol/httpbind
                  bosh urn:xmpp:xbosh}

    # Set this to 1 or 2 to get debug messages on standard output
    variable debug 0
}

# ::xmpp::transport::bosh::open --
#
#       Open connection to XMPP server. For BOSH transport this means
#       "store BOSH parameters, create XML parser, and return or call back
#       with success.
#
# Arguments:
#       server                      (ignored, -url option is used) XMPP server
#                                   hostname.
#       port                        (ignored, -url option is used) XMPP server
#                                   port.
#       -url url                    (mandatory) BOSH URL to request.
#       -streamheadercommand cmd    Command to call when server stream header
#                                   is parsed.
#       -streamtrailercommand cmd   Command to call when server stream trailer
#                                   is parsed.
#       -stanzacommand cmd          Command to call when top-level stream
#                                   stanza is parsed.
#       -eofcommand cmd             Command to call when server (or proxy)
#                                   breaks connection.
#       -command cmd                Command to call upon a successfull or
#                                   failed connect (for this transport failing
#                                   during connect is impossible).
#       -timeout timeout            Timeout for HTTP queries (it's value must
#                                   be higher than -wait).
#       -wait int                   The longest time the connection manager is
#                                   allowed to wait before responding (in
#                                   milliseconds).
#       -hold requests              Maximum number of requests the connection
#                                   manager is allowed to keep waiting.
#       -usekeys usekeys            (default true) Use security keys to
#                                   protect connection.
#       -numkeys numkeys            (default 100) Number of keys in a series.
#       -host proxyHost             Proxy hostname.
#       -port proxyPort             Proxy port.
#       -username proxyUsername     Proxy username.
#       -password proxyPassword     Proxy password.
#       -useragent proxyUseragent   Proxy useragent.
#
# Result:
#       Transport token which is to be used for communication with XMPP server.
#
# Side effects:
#       A new variable is created where BOSH options are stored. Also, a new
#       XML parser is created.

proc ::xmpp::transport::bosh::open {server port args} {
    variable id

    if {![info exists id]} {
        set id 0
    }

    set token [namespace current]::[incr id]
    variable $token
    upvar 0 $token state

    set state(transport) bosh

    set state(streamHeaderCmd)  #
    set state(streamTrailerCmd) #
    set state(stanzaCmd)        #
    set state(eofCmd)           #
    set state(-timeout)         0
    set state(-wait)            30000
    set state(-hold)            1
    set state(-url)             ""
    set state(-usekeys)         0
    set state(-numkeys)         100

    foreach {key val} $args {
        switch -- $key {
            -streamheadercommand  {set state(streamHeaderCmd)  $val}
            -streamtrailercommand {set state(streamTrailerCmd) $val}
            -stanzacommand        {set state(stanzaCmd)        $val}
            -eofcommand           {set state(eofCmd)           $val}
            -command              {set cmd                     $val}
            -timeout     -
            -wait        -
            -hold        -
            -url         -
            -usekeys     -
            -numkeys     {set state($key)    $val}
            -proxyfilter {set proxyFilter    $val}
            -host        {set proxyHost      $val}
            -port        {set proxyPort      $val}
            -username    {set proxyUsername  $val}
            -password    {set proxyPassword  $val}
            -useragent   {set proxyUseragent $val}
        }
    }

    set state(open)      0
    set state(secure)    0
    set state(outdata)   ""
    set state(keys)      {}
    set state(proxyAuth) {}
    set state(wait)      disconnected
    set state(sid)       ""
    set state(requests)  [expr {$state(-hold)+1}]
    set state(queries)   0
    set state(polling)   2000
    set state(id)        ""

    if {[info exists proxyUseragent]} {
        ::http::config -useragent $proxyUseragent
    }

    if {[info exists proxyFilter]} {
        # URLmatcher is borrowed from http package.
        set URLmatcher {(?x)                    # this is _expanded_ syntax
            ^
            (?: (\w+) : ) ?                     # <protocol scheme>
            (?: //
                (?:
                    (
                        [^@/\#?]+               # <userinfo part of authority>
                    ) @
                )?
                ( [^/:\#?]+ )                   # <host part of authority>
                (?: : (\d+) )?                  # <port part of authority>
            )?
            ( / [^\#?]* (?: \? [^\#?]* )?)?     # <path> (including query)
            (?: \# (.*) )?                      # <fragment>
            $
        }

        if {[regexp -- $URLmatcher $state(-url) -> \
                       proto user host port srvurl]} {
            if {![catch {eval $proxyFilter $host} answer]} {
                foreach {phost pport proxyUsername proxyPassword} $answer {
                    break
                }
            }
        }

        ::http::config -proxyfilter $proxyFilter
    }

    if {[info exists proxyHost] && [info exists proxyPort]} {
        ::http::config -proxyhost $proxyHost -proxyport $proxyPort
    }

    if {[info exists proxyUsername] && [info exists proxyPassword] && \
            !([string equal $proxyUsername ""] && \
              [string equal $proxyPassword ""])} {
        set auth \
            [base64::encode \
                    [encoding convertto $proxyUsername:$proxyPassword]]
        set state(proxyAuth) [list Proxy-Authorization "Basic $auth"]
    }

    if {$state(-usekeys)} {
        Debug $token 2 "generating keys"
        set state(keys) [GenKeys $state(-numkeys)]
    }

    # BOSH doesn't wrap stanzas into <stream:stream/>, so we don't need parser
    # to call back for stream header and trailer.

    set state(parser) \
        [::xmpp::xml::new # # \
                [namespace code [list InXML $token \
                                            $state(streamHeaderCmd) \
                                            $state(streamTrailerCmd) \
                                            $state(stanzaCmd)]]]

    SetWait $token connected

    if {[info exists cmd]} {
        # Asynchronous mode is almost synchronous
        CallBack $cmd [list ok $token]
    }

    return $token
}

# ::xmpp::transport::bosh::outText --
#
#       Send text to XMPP server.
#
# Arguments:
#       token           Transport token.
#       text            Text to send.
#       attrs           (optional, defaults to {}) A list of attributes for
#                       the <body/> element (body of the POST query).
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending text to the server is scheduled.

proc ::xmpp::transport::bosh::outText {token text {attrs {}}} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return -1
    }

    switch -- $state(wait) {
        disconnected -
        disconnecting {
            # TODO
            return -1
        }
        default {
            Request $token $text $attrs
        }
    }
    # TODO
    return [string bytelength $text]
}

# ::xmpp::transport::bosh::outXML --
#
#       Send XML element to XMPP server.
#
# Arguments:
#       token           Transport token.
#       xml             XML stanza to send.
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending XML to the server is scheduled.

proc ::xmpp::transport::bosh::outXML {token xml} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)] || [string equal $state(wait) disconnected]} {
        return -1
    }

    ::xmpp::xml::split $xml tag xmlns attrs1 cdata subels nextCdata

    # The default XMLNS of BOSH <body/> element is
    # http://jabber.org/protocol/httpbind, so stanzas require specifying
    # XMLNS explicitly.

    if {[string equal $xmlns ""]} {
        set xml [::xmpp::xml::merge $tag $state(xmlns) $attrs1 \
                                    $cdata $subels $nextCdata]
    }

    # HACK: Adding xmlns:stream definition if stream prefix is found
    # in the stanza

    if {[FindXMLNS $xml $state(xmlns:stream)]} {
        set attrs [list xmlns:stream $state(xmlns:stream)]
    } else {
        set attrs {}
    }

    return [outText $token [::xmpp::xml::toText $xml] $attrs]
}

# ::xmpp::transport::bosh::FindXMLNS --
#
#       Return 1 if the XML element contains the given XMLNS.
#
# Arguments:
#       xml             XML stanza to check.
#       ns              XMLNS to find.
#
# Result:
#       1 if the namespace is found, 0 otherwise.
#
# Side effects:
#       None.

proc ::xmpp::transport::bosh::FindXMLNS {xml ns} {
    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    if {[string equal $xmlns $ns]} {
        return 1
    }

    foreach subel $subels {
        if {[FindXMLNS $subel $ns]} {
            return 1
        }
    }

    return 0
}

# ::xmpp::transport::bosh::openStream --
#
#        Initiate new BOSH session.
#
# Arguments:
#       token           Transport token.
#       server          XMPP server.
#       args            Arguments for [::xmpp::xml::streamHeader].
#
# Result:
#       0
#
# Side effects:
#       Sending string to the server is scheduled.

proc ::xmpp::transport::bosh::openStream {token server args} {
    eval OpenStreamAux [list $token open $server] $args
}

# ::xmpp::transport::bosh::reopenStream --
#
#       Reopen BOSH stream.
#
# Arguments:
#       token           Transport token.
#       server          XMPP server.
#       args            Arguments for [::xmpp::xml::streamHeader].
#
# Result:
#       0
#
# Side effects:
#       Sending string to the server is scheduled.

proc ::xmpp::transport::bosh::reopenStream {token server args} {
    eval OpenStreamAux [list $token reopen $server] $args
}

# ::xmpp::transport::bosh::OpenStreamAux --
#
#        Auxiliary proc which opens or reopens BOSH session.
#
# Arguments:
#       token           Transport token.
#       mode            'open' or 'reopen'
#       server          XMPP server.
#       args            Arguments for [::xmpp::xml::streamHeader].
#
# Result:
#       0
#
# Side effects:
#       Sending string to the server is scheduled.

proc ::xmpp::transport::bosh::OpenStreamAux {token mode server args} {
    variable $token
    upvar 0 $token state
    variable ver
    variable NS

    if {![info exists state(wait)] || [string equal $state(wait) disconnected]} {
        return -1
    }

    Debug $token 2 "$mode $server $args"

    # Fake XMPP stream header (parser invokes callback for every level 1
    # stanza).

    ::xmpp::xml::parser $state(parser) parse <stream>

    set appendXmlns 0
    set attrs [list xmlns $NS(bind) ver $ver to $server]

    if {[string equal $mode open]} {
        # Opening a new stream

        lappend attrs wait [expr {int(($state(-wait)+999)/1000.0)}] \
                      hold $state(-hold)
    } else {
        # Reopening stream

        lappend attrs sid          $state(sid) \
                      xmpp:restart true
        set appendXmlnsXmpp 1
    }

    foreach {key val} $args {
        switch -- $key {
            -from {
                lappend attrs from $val
            }
            -xml:lang {
                lappend attrs xml:lang $val
            }
            -version {
                lappend attrs xmpp:version $val
                set appendXmlnsXmpp 1
            }
            -xmlns:stream {
                set state(xmlns:stream) $val
            }
            -xmlns {
                set state(xmlns) $val
            }
            default {
                return -code error [::msgcat::mc "Invalid option \"%s\"" $key]
            }
        }
    }

    if {$appendXmlnsXmpp} {
        # Define XMLNS for xmpp prefix if it was used

        lappend attrs xmlns:xmpp $NS(bosh)
    }

    set state(open) 0

    return [outText $token "" $attrs]
}

# ::xmpp::transport::bosh::closeStream --
#
#       Send XMPP stream trailer to XMPP server and start disconnecting
#       procedure.
#
# Arguments:
#       token           Transport token.
#       -wait bool      (optional, default is 0) Wait for real disconnect.
#
# Result:
#       Empty string.
#
# Side effects:
#       Sending stream trailer to the server is scheduled.

proc ::xmpp::transport::bosh::closeStream {token args} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)] || [string equal $state(wait) disconnected]} {
        return -1
    }

    Debug $token 2 ""

    set attrs [list type terminate]
    set len [outText $token "" $attrs]

    SetWait $token disconnecting

    set wait 0
    foreach {key val} $args {
        switch -- $key {
            -wait {
                set wait $val
            }
        }       
    }

    if {$wait} {
        while {[info exists state(wait)] && \
                            ![string equal $state(wait) disconnected]} {
            vwait $token\(wait)
        }
    }

    return $len
}

# ::xmpp::transport::bosh::flush --
#
#       Flush XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Pending data is sent to the server.

proc ::xmpp::transport::bosh::flush {token} {
    # TODO
}

# ::xmpp::transport::bosh::ip --
#
#       Return IP of an outgoing socket.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string (until really implemented).
#
# Side effects:
#       None.

proc ::xmpp::transport::bosh::ip {token} {
    variable $token
    upvar 0 $token state

    # TODO
    return ""
}

# ::xmpp::transport::bosh::close --
#
#       Close XMPP channel.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       Transport token and XML parser are destroyed.

proc ::xmpp::transport::bosh::close {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        # The channel is already closed
        return
    }

    SetWait $token disconnected

    if {[info exists state(parser)]} {
        ::xmpp::xml::free $state(parser)
    }

    catch {unset state}
    return
}

# ::xmpp::transport::bosh::reset --
#
#       Reset XMPP stream.
#
# Arguments:
#       token           Transport token.
#
# Result:
#       Empty string.
#
# Side effects:
#       XML parser is reset.

proc ::xmpp::transport::bosh::reset {token} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)] || [string equal $state(wait) disconnected]} {
        return
    }

    Debug $token 2 ""

    ::xmpp::xml::reset $state(parser)
    return
}

# ::xmpp::transport::bosh::InText --
#
#       A helper procedure which is called when a new portion of data is
#       received from XMPP server. It feeds XML parser with this data.
#
# Arguments:
#       token           Transport token.
#       text            Text to parse.
#
# Result:
#       Empty string.
#
# Side effects:
#       The text is parsed and if it completes top-level stanza then an
#       appropriate callback is invoked.

proc ::xmpp::transport::bosh::InText {token text} {
    variable $token
    upvar 0 $token state

    Debug $token 2 $text

    ::xmpp::xml::parser $state(parser) parse $text

    return
}

# ::xmpp::transport::bosh::InXML --
#
#       A helper procedure which is called when a new XML stanza is parsed.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       token           Transport token.
#       headerCmd       Command to call if XMPP session is started.
#       trailerCmd      Command to call if XMPP session is ended.
#       stanzaCmdmd     Command to call if XMPP stanza is received.
#       xml             BOSH body XML stanza.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the specified command is called.

proc ::xmpp::transport::bosh::InXML {token headerCmd trailerCmd stanzaCmd xml} {
    variable $token
    upvar $token state
    variable NS

    Debug $token 2 "$state(open) $xml"

    ::xmpp::xml::split $xml tag xmlns attrs cdata subels

    if {![string equal $xmlns $NS(bind)]} {
        return -code error "Unexpected XMLNS in BOSH reply: $xmlns"
    }

    set type ""
    set condition ""
    foreach {key val} $attrs {
        switch -- $key \
            sid {
                set state(sid) $val
            } \
            wait {
                set state(-wait) [expr {$val*1000}]
            } \
            ver {
                set state(var) $val
            } \
            polling {
                set state(polling) [expr {$val*1000}]
            } \
            inactivity {
                # TODO
            } \
            requests {
                set requests $val
            } \
            maxpause {
                # TODO
            } \
            secure {
                set state(secure) $val
            } \
            accept {
                # TODO
            } \
            ack {
                # TODO
            } \
            hold {
                set state(-hold) $val
            } \
            from {
                set state(-from) $val
            } \
            $NS(bosh):version {
                set state(-version) $val
            } \
            authid {
                set state(-id) $val
            } \
            type {
                set type $val
            } \
            condition {
                set condition $val
            }
    }

    if {![info exists requests]} {
        set state(requests) [expr {$state(-hold)+1}]
    } else {
        set state(requests) $requests
    }

    if {!$state(open)} {
        set newattrs {}
        foreach key {from version id} {
            if {[info exists state(-$key)]} {
                lappend newattrs $key $state(-$key)
            }
        }

        set state(open) 1
        CallBack $headerCmd [list $newattrs]
    }

    # Process received stanzas

    foreach subel $subels {
        CallBack $stanzaCmd [list $subel]
    }

    if {[string equal $type terminate]} {
        SetWait $token disconnected
        CallBack $state(eofCmd)
    }

    return
}

# ::xmpp::transport::bosh::CallBack --
#
#       A helper procedure which is called when XMPP stream is finished.
#       It then calls a specified command as an idle callback.
#
# Arguments:
#       cmd             Command to call.
#
# Result:
#       Empty string.
#
# Side effects:
#       After entering event loop the specified command is called.

proc ::xmpp::transport::bosh::CallBack {cmd args} {
    eval [list after idle $cmd] $args
    return
}

# ::xmpp::transport::bosh::Body --
#
#       Create textual representation of BOSH body XML element.
#
# Arguments:
#       token       Tranport token.
#       attrs       Attribute key-value pairs list.
#       text        (Optional, defaults to empty string) Textual representation
#                   of body subelements.
#
# Result:
#       BOSH body XML element.
#
# Side effects:
#       None.

proc ::xmpp::transport::bosh::Body {token attrs {text ""}} {
    variable $token
    upvar 0 $token state
    variable NS

    if {![::xmpp::xml::isAttr $attrs xmlns]} {
        set attrs [linsert $attrs 0 xmlns $NS(bind) \
                                    sid   $state(sid)]
    }

    # We have to construct body XML element by hands to be able to put
    # arbitrary text inside it.
    set retext "<body"
    foreach {attr value} $attrs {
        append retext " $attr='[::xmpp::xml::Escape $value]'"
    }
    if {[string equal $text ""]} {
        append retext "/>"
    } else {
        append retext ">$text</body>"
    }

    return $retext
}

# ::xmpp::transport::bosh::Request --
#
#       Schedule BOSH request procedure to output given text.
#
# Arguments:
#       token               Tranport token.
#       text                Text to output.
#
# Result:
#       Empty string.
#
# Side effects:
#       If there's no request which is waited for then a new request is sent,
#       otherwise a new call to [Request] is scheduled.

proc ::xmpp::transport::bosh::Request {token text attrs} {
    variable $token
    upvar 0 $token state

    Debug $token 2 "'$text' '$attrs'"

    if {![info exists state(wait)]} {
        # Trying to poll an already closed connection
        Debug $token 2 NON-EXISTENT
        return
    }

    append state(outdata) $text

    switch -- $state(wait) {
        disconnected {
            Debug $token 2 DISCONNECTED

            return
        }
        disconnecting {
            Debug $token 2 DISCONNECTING

            return
        }
        default {
            if {![string equal [::xmpp::xml::getAttr $attrs type] terminate] && \
                ($state(queries) >= $state(requests) || \
                ($state(queries) > 0 && [string equal $state(outdata) ""]))} {
                Debug $token 2 RESCHEDULING

                after cancel $state(id)
                set state(id) \
                    [after $state(polling) \
                           [namespace code [list Request $token "" {}]]]
                return
            }
        }
    }

    set newattrs $attrs
    if {![info exists state(rid)]} {
        # The first request ever

        set state(rid) [expr {round(rand()*10000000)}]

        if {$state(-usekeys)} {
            # Won't work with number of keys equal to 1 (which is ridiculous
            # anyway)

            lappend newattrs newkey [lindex $state(keys) end]
            set state(keys) [lrange $state(keys) 0 end-1]
        }
    } else {
        # The next request ID

        set state(rid) [NextRid $state(rid)]

        if {$state(-usekeys)} {
            lappend newattrs key [lindex $state(keys) end]
            set state(keys) [lrange $state(keys) 0 end-1]

            if {[llength $state(keys)] == 0} {
                # Regenerate keys

                Debug $token 2 "Regenerating keys"
                set state(keys) [GenKeys $state(-numkeys)]

                lappend newattrs newkey [lindex $state(keys) end]
                set state(keys) [lrange $state(keys) 0 end-1]
            }
        }
    }

    set query [Body $token [linsert $newattrs 0 rid $state(rid)] $state(outdata)]

    Debug $token 2 "query: '$query'"

    incr state(queries)
    set state(outdata) ""

    after cancel $state(id)
    set state(id) \
        [after $state(polling) [namespace code [list Request $token "" {}]]]

    GetURL $token 0 [encoding convertto utf-8 $query]
    return
}

# ::xmpp::transport::bosh::ProcessReply --
#
#       Process BOSH reply from the XMPP server.
#
# Arguments:
#       token               Tranport token.
#       try                 Number of the previous requests of the same query.
#       query               Query string.
#       httpToken           HTTP token to get server answer.
#
# Result:
#       Empty string.
#
# Side effects:
#       If query failed then it is retried (not more than thrice), otherwise the
#       answer is received and pushed to XML parser.

proc ::xmpp::transport::bosh::ProcessReply {token try query httpToken} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        # A reply for an already closed connection
        return
    }

    upvar #0 $httpToken httpState

    if {[::http::ncode $httpToken] != 200} {
        Debug $token 1 "HTTP returned [::http::ncode $httpToken]\
                                      [http::status $httpToken]"
        Debug $token 2 "[::http::meta $httpToken]"
        Debug $token 2 "[::http::data $httpToken]"

        if {$try < 3} {
            GetURL $token [incr try] $query
        } else {
            # Don't care about state(queries) since the connection is broken

            SetWait $token disconnected
            CallBack $state(eofCmd)
        }
        ::http::cleanup $httpToken
        return
    }

    incr state(queries) -1
    if {$state(queries) < 0} {
        # Something wrong, received more replies then sent

        Debug $token 1 "state(queries) < 0"
        set state(queries) 0
    }

    Debug $token 2 [::http::meta $httpToken]

    set inmsg [encoding convertfrom utf-8 [::http::data $httpToken]]
    ::http::cleanup $httpToken

    Debug $token 2 '$inmsg'

    InText $token $inmsg
}

# ::xmpp::transport::bosh::GetURL --
#
#       Fetch BOSH URL.
#
# Arguments:
#       token               Transport token.
#       try                 Number of previous tries of the same query
#                           (sometimes query fails because of proxy errors, so
#                           it's better to try once more).
#       query               Query to send to the server.
#
# Result:
#       Empty string.
#
# Side effects:
#       BOSH HTTP request is sent and ProcessReply call is scheduled on reply.

proc ::xmpp::transport::bosh::GetURL {token try query} {
    variable $token
    upvar 0 $token state

    Debug $token 2 $try

    # Option -keepalive 1 (which reuse open sockets - a good thing) doesn't
    # work well if we do multiple requests in parallel, so do open a separate
    # socket for every request (which creates a lot of overhead, but...)

    ::http::geturl $state(-url) \
                   -binary  1 \
                   -keepalive 0 \
                   -headers $state(proxyAuth) \
                   -type    "text/xml; charset=utf-8" \
                   -query   $query \
                   -timeout $state(-timeout) \
                   -command [namespace code [list ProcessReply $token \
                                                               $try \
                                                               $query]]
    return
}

# ::xmpp::transport::bosh::SetWait --
#
#       Set polling state for a given connection (if it exists) and if the
#       state is "disconnected" then cancel future requesting attempts.
#
# Arguments:
#       token           Tranport token.
#       opt             State name ("connected", "disconnecting",
#                       "disconnected").
#
# Result:
#       Empty string.
#
# Side effects:
#       Polling state is changed. If it becomes "disconnected" then the next
#       requesting attempt is canceled.

proc ::xmpp::transport::bosh::SetWait {token opt} {
    variable $token
    upvar 0 $token state

    if {![info exists state(wait)]} {
        return
    }

    set state(wait) $opt

    switch -- $opt {
        disconnected {
            after cancel $state(id)
        }
    }

    return
}

# ::xmpp::transport::bosh::NextRid --
#
#       Return the next request ID.
#
# Arguments:
#       rid                 The current request ID.
#
# Result:
#       Incremented request ID. If it is greater than 2^53, the result is 0.
#
# Side effects:
#       None.

proc ::xmpp::transport::bosh::NextRid {rid} {
    incr rid
    if {$rid > 0 && $rid <= 1<<53} {
        return $rid
    } else {
        return 0
    }
}

# ::xmpp::transport::bosh::GenKeys --
#
#       Generate a sequence of security keys (see XEP-0124 section 15 for
#       details).
#
# Arguments:
#       numKeys             Number of keys to generate.
#
# Result:
#       List of keys.
#
# Side effects:
#       None.

proc ::xmpp::transport::bosh::GenKeys {numKeys} {
    set seed [expr {round(1000000000 * rand())}]
    set oldKey $seed
    set keys {}

    while {$numKeys > 0} {
        set nextKey [sha1::sha1 $oldKey]
        # Skip the initial seed
        lappend keys $nextKey
        set oldKey $nextKey
        incr numKeys -1
    }
    return $keys
}

# ::xmpp::transport::bosh::Debug --
#
#       Print debug information.
#
# Arguments:
#       token   Transport token.
#       level   Debug level.
#       str     Debug message.
#
# Result:
#       An empty string.
#
# Side effects:
#       A debug message is printed to the console if the value of
#       ::xmpp::transport::bosh::debug variable is not less than num.

proc ::xmpp::transport::bosh::Debug {token level str} {
    variable debug

    if {$debug >= $level} {
        puts "[clock format [clock seconds] -format %T]\
              [lindex [info level -1] 0] $token $str"
    }

    return
}

# vim:ts=8:sw=4:sts=4:et
