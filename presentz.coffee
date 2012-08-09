express = require "express"
orient = require "orientdb"
cons = require "consolidate"
OrientDBStore = require("connect-orientdb")(express)
_ = require "underscore"

redirect_routes = require "./routes_redirect"
auth = require "./auth"
assets = require "./assets"
api = require "./api"
routes = require "./routes"

Number:: pad = (pad, pad_char = "0") ->
  s = @.toString()
  while s.length < pad
    s = "#{pad_char}#{s}"
  s

app = express()

config = require "./config.#{app.settings.env}"

server = new orient.Server config.storage.server

db = new orient.GraphDb "presentz", server, config.storage.db

db.open (err) ->
  throw new Error(err) if err?
  console.log("DB connection open")

session_store_options = _.clone(config.storage)
session_store_options.database = "presentz"

everyauth = auth.init(config, db)
api.init(db)
routes.init(db)

app.engine("dust", cons.dust)

app.configure ->
  app.set "views", "#{__dirname}/views"
  app.set "view engine", "dust"
  app.enable "view cache"
  app.use express.logger()
  app.use express.bodyParser()
  app.use express.cookieParser(config.presentz.session_secret)
  app.use assets.assetsMiddleware
  app.use express.session
    store: new OrientDBStore(session_store_options)
  app.use express.methodOverride()
  app.use everyauth.middleware()
  app.use auth.put_user_in_locals
  app.use app.router
  app.use express.static "#{__dirname}/public"
  app.use redirect_routes.redirect_to "/"

app.configure "development", ->
  app.use express.errorHandler { dumpExceptions: true, showStack: true }

app.configure "test", ->
  app.use express.errorHandler { dumpExceptions: true, showStack: true }

app.configure "production", ->
  app.use express.errorHandler()

app.locals
  assetsCacheHashes: assets.assetsMiddleware.cacheHashes

app.get "/", routes.static_view "index"
app.get "/favicon.ico", express.static "#{__dirname}/public/assets/img"
app.get "/robots.txt", express.static "#{__dirname}/public/assets"
app.get "/r/back_to_referer", redirect_routes.back_to_referer config
app.get "/r/index.html", routes.static_view "index"
app.get "/r/tos.html", routes.static_view "tos"
app.get "/r/talks.html", routes.list_catalogs
app.all "/m/*", routes.ensure_is_logged
app.get "/m/index.html", routes.static_view "m/index"
app.get "/m/api/my_presentations", api.my_presentations
app.get "/:catalog_name/catalog.html", routes.show_catalog
app.get "/:catalog_name/catalog", routes.show_catalog
app.get "/:catalog_name/index.html", routes.show_catalog
app.get "/:catalog_name/:presentation.json", routes.raw_presentation
app.get "/:catalog_name/:presentation", routes.show_presentation
app.get "/:catalog_name", routes.show_catalog
app.post "/:catalog_name/:presentation/comment", routes.comment_presentation

app.listen config.port
console.log "Express server listening on port #{config.port} in #{app.settings.env} mode"

require "./subdomain"