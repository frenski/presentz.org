###
Presentz.org - A website to publish presentations with video and slides synchronized.

Copyright (C) 2012 Federico Fissore

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
###

"use strict"

_ = require "underscore"
dateutil = require "dateutil"
moment = require "moment"

utils = require "./utils"
dustjs_helpers = require "./dustjs_helpers"
draw_4_boxes = dustjs_helpers.draw_boxes(4)
draw_6_boxes = dustjs_helpers.draw_boxes(6)

storage = undefined
auth = undefined

pretty_duration = (seconds, minutes_char = "'", seconds_char = "\"") ->
  duration = moment.duration(Math.round(seconds), "seconds")
  "#{duration.minutes().pad(2)}#{minutes_char}#{duration.seconds().pad(2)}#{seconds_char}"

list_catalogs = (req, res, next) ->
  storage.list_catalogs_with_presentation_count (err, catalogs) ->
    return next(err) if err?

    render_ctx =
      title: "Presentz featured talks"
      head_title: "Featured talks - Presentz"
      css_section_talks: "selected"
      catalogs: catalogs
      list: draw_6_boxes
    render_ctx.head_description = render_ctx.title

    res.render "catalogs", render_ctx

pres_to_thumb = (presentation, catalog_name) ->
  pres =
    id: presentation.id
    catalog: catalog_name
    thumb: presentation.chapters[0].video.thumb
    speaker: presentation.speaker
    title: presentation.title
    description: presentation.title

  pres.time = dateutil.format(dateutil.parse(presentation.time, "YYYYMMDD"), "Y/m") if presentation.time
  pres

show_catalog = (req, res, next) ->
  storage.catalog_name_to_node req.params.catalog_name, (err, catalog) ->
    return next(err) if err?

    storage.from_catalog_to_presentations catalog, (err, presentations) ->
      return next(err) if err?
      presentations = _.filter presentations, (pres) -> pres.published
      presentations = (pres_to_thumb(pres, req.params.catalog_name) for pres in presentations)
      presentations = _.sortBy presentations, (presentation) ->
        return presentation.time if presentation.time?
        return presentation.title

      if presentations[0].time?
        presentations = presentations.reverse()

      render_ctx =
        title: catalog.name
        head_title: "#{catalog.name} - Presentz"
        catalog: catalog
        presentations: presentations
        list: draw_4_boxes
      render_ctx.head_description = render_ctx.title
      if catalog.description? and catalog.description isnt ""
        render_ctx.head_description = catalog.description
        render_ctx.subtitle = catalog.description

      res.render "talks", render_ctx

show_catalog_of_user = (social) ->
  return (req, res, next) ->
    storage.find_user_by_username_by_social social.col, req.params.user_name, (err, user) ->
      return next(err) if err?

      storage.from_user_to_presentations user, (err, presentations) ->
        presentations = _.filter presentations, (pres) -> pres.published

        if presentations.length > 0
          presentations = (pres_to_thumb(pres, "u/#{social.prefix}/#{user.user_name}") for pres in presentations)
          presentations = _.sortBy presentations, (presentation) ->
            return presentation.time if presentation.time?
            return presentation.title

          if presentations[0].time?
            presentations = presentations.reverse()

        if req.user? and req.user.user_name is req.params.user_name
          is_same_user = true
        else
          is_same_user = false

        render_ctx =
          title: "#{user.name}'s talks"
          head_title: "#{user.name}'s talks - Presentz"
          presentations: presentations
          is_same_user: is_same_user
          list: draw_4_boxes
        render_ctx.head_description = render_ctx.title

        res.render "talks", render_ctx

raw_presentation_from_catalog = (req, res, next) ->
  storage.load_entire_presentation_from_catalog req.params.catalog_name, req.params.presentation, (err, presentation) ->
    return next(err) if err?

    raw_presentation presentation, req, res

raw_presentation_from_user = (req, res, next) ->
  auth.social_column_from_prefix req.params.social_prefix, (err, social_column) ->
    return next(err) if err?

    storage.load_entire_presentation_from_users_catalog social_column, req.params.user_name, req.params.presentation, (err, presentation) ->
      return next(err) if err?

      raw_presentation presentation, req, res, (req.headers.referer? and req.headers.referer.indexOf("preview") isnt -1)

raw_presentation = (presentation, req, res, preview) ->
  return res.send 404 unless presentation.published or preview

  utils.visit_presentation presentation, utils.remove_unwanted_fields_from, [ "id", "out", "_type", "_index", "@class", "@type", "@version", "@rid", "user" ]

  if req.query.jsoncallback
    presentation = "#{req.query.jsoncallback}(#{JSON.stringify(presentation)});"
    res.contentType("text/javascript")
  else
    res.contentType("application/json")

  res.send presentation

show_presentation_from_catalog = (req, res, next) ->
  path = "#{req.params.catalog_name}/#{req.params.presentation}"
  storage.load_entire_presentation_from_catalog req.params.catalog_name, req.params.presentation, (err, presentation) ->
    return next(err) if err?

    show_presentation presentation, path, req, res

show_presentation_from_user = (req, res, next) ->
  path = "u/#{req.params.social_prefix}/#{req.params.user_name}/#{req.params.presentation}"
  auth.social_column_from_prefix req.params.social_prefix, (err, social_column) ->
    return next(err) if err?

    storage.load_entire_presentation_from_users_catalog social_column, req.params.user_name, req.params.presentation, (err, presentation) ->
      return next(err) if err?

      show_presentation presentation, path, req, res, req.query.preview

show_presentation = (presentation, path, req, res, preview) ->
  return res.send 404 unless presentation.published or preview?

  comments_of = (presentation) ->
    comments = []
    for comment in presentation.comments
      comment.nice_time = moment(comment.time).fromNow()
      comments.push comment

    for chapter, chapter_index in presentation.chapters
      for slide, slide_index in chapter.slides
        for comment in slide.comments
          comment.slide_title = slide.title or "Slide #{slide_index + 1}"
          comment.nice_time = moment(comment.time).fromNow()
          comment.slide_index = slide_index
          comment.chapter_index = chapter_index
          comments.push comment

    comments

  slide_to_slide = (slide, chapter_index, slide_index, duration) ->
    slide.title = "Slide #{ slide_index + 1 }" if !slide.title?
    slide.chapter_index = chapter_index
    slide.slide_index = slide_index
    slide.time = slide.time + duration
    if slide.comments?
      slide.comments_length = slide.comments.length
    else
      slide.comments_length = 0
    if slide.comments_length is 1
      slide.comments_label = "comment"
    else
      slide.comments_label = "comments"
    slide

  slides_duration_percentage_css = (slides, duration) ->
    percent_per_second = 100 / duration
    percent_used = 0
    duration_used = 0
    number_of_zeros_in_index = slides.length.toString().length
    for slide, slide_num in slides
      if slide_num + 1 < slides.length
        slide.duration = slides[slide_num + 1].time - slide.time
        slide.percentage = slide.duration * percent_per_second
        percent_used += slide.percentage
      else
        slide.duration = duration - slide.time
        slide.percentage = 100 - percent_used
      duration_used += slide.duration
      percent_per_second = (100 - percent_used) / (duration - duration_used)
      slide.duration = pretty_duration slide.duration
      slide.index = (slide_num + 1).pad(number_of_zeros_in_index)
      slide.css = "class=\"even\"" if slide.index % 2 is 0

  slides = []
  duration = 0
  for chapter, chapter_index in presentation.chapters
    for slide, slide_index in chapter.slides
      slides.push slide_to_slide(slide, chapter_index, slide_index, duration)
    if !chapter.duration? and chapter.slides? and chapter.slides.length > 0
      chapter.duration = chapter.slides[chapter.slides.length - 1].time + 5
    duration += chapter.duration

  slides_duration_percentage_css(slides, duration)

  title_parts = presentation.title.trim().split(" ")
  title_parts[title_parts.length - 1] = "<span>#{title_parts[title_parts.length - 1]}</span>"
  talk_title = title_parts.join(" ")
  pres_title = presentation.title
  pres_title = "#{pres_title} - #{presentation.speaker}" if presentation.speaker? and presentation.speaker isnt ""

  comments = comments_of presentation

  res.render "presentation",
    title: pres_title
    head_title: "#{pres_title} - Presentz"
    head_description: pres_title #TODO add a description to the presentation
    talk_title: talk_title
    speaker: presentation.speaker
    slides: slides
    comments: comments
    domain: "http://#{req.headers.host}"
    path: path
    thumb: presentation.chapters[0].video.thumb
    wrapper_css: "class=\"section_player\""
    embed: req.query.embed?

comment_presentation = (req, res, next) ->
  return res.send 401 if !req.user?

  params = req.body

  get_node_to_link_to = (callback) ->
    storage.load_entire_presentation_from_id req.params.presentation, (err, presentation) ->
      return callback(err) if err?
      return callback(undefined, undefined) unless presentation.published

      node_to_link_to = presentation

      if params.chapter? and params.chapter isnt "" and params.slide? and params.slide isnt ""
        node_to_link_to = presentation.chapters[params.chapter].slides[params.slide]

      callback(undefined, node_to_link_to)

  save_and_link_comment = (node_to_link_to, callback) ->
    comment =
      _type: "comment"
      text: params.comment
      time: new Date()

    storage.create_comment comment, node_to_link_to, req.user, callback

  get_node_to_link_to (err, node_to_link_to) ->
    return next(err) if err?

    return res.send 404 unless node_to_link_to

    save_and_link_comment node_to_link_to, (err, comment) ->
      return res.send 500 if err?

      comment.user = req.user
      comment.chapter_index = params.chapter
      comment.slide_index = params.slide
      comment.nice_time = moment(comment.time).fromNow()
      if node_to_link_to._type is "slide"
        comment.slide_title = node_to_link_to.title or "Slide #{parseInt(params.slide) + 1}"

      res.render "_comment_",
        comment: comment

static_view = (view_name, title, head_title, head_description) ->
  return (req, res) ->
    options =
      title: title
      head_title: head_title
      head_description: head_description
    options["css_section_#{view_name}"] = "selected"
    res.render view_name, options

ensure_is_logged = (req, res, next) ->
  return next() if req.user?

  #req.notify "error", "you need to be logged in"
  res.redirect 302, "/"

init = (s, a) ->
  storage = s
  auth = a

exports.list_catalogs = list_catalogs
exports.show_catalog = show_catalog
exports.show_catalog_of_user = show_catalog_of_user
exports.show_presentation_from_user = show_presentation_from_user
exports.show_presentation_from_catalog = show_presentation_from_catalog
exports.raw_presentation_from_catalog = raw_presentation_from_catalog
exports.raw_presentation_from_user = raw_presentation_from_user

exports.comment_presentation = comment_presentation
exports.static_view = static_view
exports.ensure_is_logged = ensure_is_logged

exports.init = init