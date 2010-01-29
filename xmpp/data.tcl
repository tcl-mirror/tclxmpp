# data.tcl --
#
#       This file is a part of the XMPP library. It implements support for
#       data forms (XEP-0004) and data forms media items (XEP-0221).
#
# Copyright (c) 2008-2010 Sergei Golovan <sgolovan@nes.ru>
#
# See the file "license.terms" for information on usage and redistribution
# of this file, and for a DISCLAMER OF ALL WARRANTIES.
#
# $Id$

package require xmpp::xml

package provide xmpp::data 0.1

namespace eval ::xmpp::data {}

# ::xmpp::data::formField --

proc ::xmpp::data::formField {tag args} {
    array set params $args

    switch -- $tag {
        instructions -
        title {
            if {[info exists params(-value)]} {
                return [list $tag $params(-value)]
            } else {
                return -code error "You must define -value"
            }
        }
        field {
            if {[info exists params(-var)]} {
                set field [list $params(-var)]
            } elseif {![string equal $type fixed]} {
                return -code error "You must define -var"
            }

            if {[info exists params(-type)]} {
                set type $params(-type)
                lappend field $params(-type)
            } else {
                set type ""
                lappend field ""
            }

            if {[info exists params(-label)]} {
                lappend field $params(-label)
            } else {
                lappend field ""
            }

            if {[info exists params(-desc)]} {
                lappend field $params(-desc)
            } else {
                lappend field ""
            }

            if {[info exists params(-required)]} {
                lappend field $params(-required)
            } else {
                lappend field 0
            }

            if {[lcontain {list-multi list-single} $type]} {
                if {[info exists params(-options)]} {
                    lappend field $params(-options)
                } else {
                    return -code error "You must define -options"
                }
            } else {
                lappend field {}
            }

            if {[lcontain {jid-multi text-multi list-multi} $type]} {
                if {[info exists params(-values)]} {
                    lappend field $params(-values)
                } elseif {[lcontain {jid-multi} $type]} {
                    return -code error "You must define -values"
                } else {
                    lappend field {}
                }
            } else {
                if {[info exists params(-value)]} {
                    lappend field [list $params(-value)]
                } elseif {[lcontain {hidden fixed} $type]} {
                    return -code error "You must define -value"
                } else {
                    lappend field {}
                }
            }

            return [list field $field]
        }
        default {
            return -code error "Unknown type $type"
        }
    }
}

# ::xmpp::data::form --

proc ::xmpp::data::form {fields} {
    set subels {}
    foreach {tag field} $fields {
        switch -- $tag {
            title {
                lappend subels [::xmpp::xml::create title -cdata $field]
            }
            instructions {
                lappend subels [::xmpp::xml::create instructions -cdata $field]
            }
            field {
                foreach {var type label desc required options values} $field break

                set attrs [list var $var]
                if {![string equal $type ""]} {
                    lappend attrs type $type
                }
                if {![string equal $label ""]} {
                    lappend attrs label $label
                }

                set fsubels {}

                if {![string equal $desc ""]} {
                    lappend fsubels [::xmpp::xml::create desc -cdata $desc]
                }

                if {$required} {
                    lappend fsubels [::xmpp::xml::create required]
                }

                foreach value $values {
                    lappend fsubels [::xmpp::xml::create value -cdata $value]
                }

                foreach {olabel ovalue} $options {
                    if {[string equal $olabel ""]} {
                        set oattrs {}
                    } else {
                        set oattrs [list label $olabel]
                    }

                    lappend fsubels [::xmpp::xml::create option \
                                            -attrs $oattrs \
                                            -subelement [::xmpp::xml::create value \
                                                                -cdata $ovalue]]
                }

                lappend subels [::xmpp::xml::create field \
                                        -attrs $attrs \
                                        -subelements $fsubels]
            }
        }
    }

    return [::xmpp::xml::create x \
                    -xmlns jabber:x:data \
                    -attrs [list type form] \
                    -subelements $subels]
}

# ::xmpp::data::cancelForm --

proc ::xmpp::data::cancelForm {} {
    return [::xmpp::xml::create x \
                    -xmlns jabber:x:data \
                    -attrs [list type cancel]]
}

# ::xmpp::data::submitForm --

proc ::xmpp::data::submitForm {fields} {
    set subels {}
    foreach {var values} $fields {
        set vsubels {}
        foreach value $values {
            lappend vsubels [::xmpp::xml::create value -cdata $value]
        }
        lappend subels [::xmpp::xml::create field \
                                -attrs [list var $var] \
                                -subelements $vsubels]
    }

    return [::xmpp::xml::create x \
                    -xmlns jabber:x:data \
                    -attrs [list type submit] \
                    -subelements $subels]
}

# ::xmpp::data::resultForm --
# TODO: Add items support.

proc ::xmpp::data::resultForm {fields} {
    set subels {}
    foreach {tag field} $fields {
        switch -- $tag {
            title {
                lappend subels [::xmpp::xml::create title -cdata $field]
            }
            field {
                foreach {var type label values} $field break

                set attrs [list var $var]
                if {![string equal $type ""]} {
                    lappend attrs type $type
                }
                if {![string equal $label ""]} {
                    lappend attrs label $label
                }

                set fsubels {}
                foreach value $values {
                    lappend fsubels [::xmpp::xml::create value -cdata $value]
                }

                lappend subels [::xmpp::xml::create field \
                                        -attrs $attrs \
                                        -subelements $fsubels]
            }
        }
    }

    return [::xmpp::xml::create x \
                    -xmlns jabber:x:data \
                    -attrs [list type result] \
                    -subelements $subels]
}

# ::xmpp::data::findForm --

proc ::xmpp::data::findForm {xmlElements} {
    foreach xmlElement $xmlElements {
        ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels
        if {[string equal $xmlns jabber:x:data]} {
            set type [::xmpp::xml::getAttr $attrs type form]
            return [list $type $xmlElement]
        }
    }
    return {{} {}}
}

# ::xmpp::data::parseForm --

proc ::xmpp::data::parseForm {xmlElement} {
    set res {}

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            instructions {
                lappend res instructions $scdata
            }
            title {
                lappend res title $scdata
            }
            field {
                lappend res field [ParseField $subel]
            }
        }
    }
    return $res
}

# ::xmpp::data::parseSubmit --

proc ::xmpp::data::parseSubmit {xmlElement} {
    set res {}

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            field {
                set type  [::xmpp::xml::getAttr $sattrs type]
                set var   [::xmpp::xml::getAttr $sattrs var]
                set label [::xmpp::xml::getAttr $sattrs label]
                set values {}
                foreach ssubel $ssubels {
                    ::xmpp::xml::split $ssubel \
                                       sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag value]} {
                        lappend values $sscdata
                    }
                }
                lappend res field [list $var $type $label $values]
            }
        }
    }

    return $res
}

# ::xmpp::data::parseResult --

proc ::xmpp::data::parseResult {xmlElement} {
    set res {}

    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    foreach subel $subels {
        ::xmpp::xml::split $subel stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            title {
                lappend res title $scdata
            }
            reported {
                set reported {}
                foreach field $ssubels {
                    ::xmpp::xml::split $field \
                                       sstag ssxmlns ssattrs sscdata sssubels

                    set var   [::xmpp::xml::getAttr $ssattrs var]
                    set label [::xmpp::xml::getAttr $ssattrs label]
                    lappend reported $var $label
                }
                lappend res reported $reported
            }
            item {
                set fields {}
                foreach field $ssubels {
                    ::xmpp::xml::split $field \
                                       sstag ssxmlns ssattrs sscdata sssubels

                    if {![string equal $sstag field]} continue

                    set var [::xmpp::xml::getAttr $ssattrs var]
                    set values {}

                    foreach value $sssubels {
                        ::xmpp::xml::split $value s3tag s3xmlns s3attrs s3cdata s3subels

                        if {[string equal $s3tag value]} {
                            lappend values $s3cdata
                        }
                    }
                    lappend fields $var $values
                }
                lappend res item $fields
            }
            field {
                set type  [::xmpp::xml::getAttr $sattrs type]
                set var   [::xmpp::xml::getAttr $sattrs var]
                set label [::xmpp::xml::getAttr $sattrs label]
                set values {}
                foreach ssubel $ssubels {
                    ::xmpp::xml::split $ssubel \
                                       sstag ssxmlns ssattrs sscdata sssubels

                    if {[string equal $sstag value]} {
                        lappend values $sscdata
                    }
                }
                lappend res field [list $var $type $label $values]
            }
        }
    }

    return $res
}

# ::xmpp::data::ParseField --

proc ::xmpp::data::ParseField {xmlElement} {
    ::xmpp::xml::split $xmlElement tag xmlns attrs cdata subels

    set required 0
    set desc     {}
    set options  {}
    set values   {}
    set media    {}

    set var   [::xmpp::xml::getAttr $attrs var]
    set type  [::xmpp::xml::getAttr $attrs type]
    set label [::xmpp::xml::getAttr $attrs label]

    foreach item $subels {
        ::xmpp::xml::split $item stag sxmlns sattrs scdata ssubels

        switch -- $stag {
            required {
                set required 1
            }
            value {
                lappend values $scdata
            }
            desc {
                set desc $scdata
            }
            option {
                set slabel [::xmpp::xml::getAttr $sattrs label]
                foreach sitem $ssubels {
                    ::xmpp::xml::split $sitem \
                                       sstag ssxmlns ssattrs sscdata sssubels
                    switch -- $sstag {
                        value {
                            set svalue $sscdata
                        }
                    }
                }
                lappend options $slabel $svalue
            }
            media {
                if {[string equal $sxmlns urn:xmpp:media-element]} {
                    set mitem {}

                    foreach sitem $ssubels {
                        ::xmpp::xml::split $sitem \
                                           sstag ssxmlns ssattrs \
                                           sscdata sssubels
                        switch -- $sstag {
                            uri {
                                if {![::xmpp::xml::isAttr $ssattrs type]} {
                                    continue
                                }
                                set mtype [::xmpp::xml::getAttr $ssattrs type]
                                set uri $sscdata

                                lappend mitem $mtype $uri
                            }
                        }
                    }

                    lappend media $mitem
                }
            }
        }
    }

    return [list $var $type $label $desc $required $options $values $media]
}

# vim:ft=tcl:ts=8:sw=4:sts=4:et
