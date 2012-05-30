express = require "express"
messages = require "bootstrap-express-messages"
redirect_routes = require "./routes_redirect"
orient = require "orientdb"
cons = require "consolidate"
OrientDBStore = require("connect-orientdb")(express)
_ = require "underscore"

app = express()

config = require "./config.#{app.settings.env}"

server = new orient.Server config.storage.server

db = new orient.GraphDb "presentz", server, config.storage.db

db.open ->
  console.log("DB connection open")

session_store_options = _.clone(config.storage)
session_store_options.database = "presentz"

everyauth = require("./auth").init(config, db)
api = require("./api").init(db)
routes = require("./routes").init(db)

app.engine("dust", cons.dust)

app.configure ->
  app.set "views", "#{__dirname}/views"
  app.set "view engine", "dust"
  app.use express.logger()
  app.use express.bodyParser()
  app.use express.cookieParser(config.presentz.session_secret)
  app.use express.session
    store: new OrientDBStore(session_store_options)
  app.use messages(app)
  app.use express.methodOverride()
  app.use everyauth.middleware()
  app.use app.router
  app.use express.static "#{__dirname}/public"
  app.use redirect_routes.redirect_to "/"

app.configure "development", ->
  app.use express.errorHandler { dumpExceptions: true, showStack: true }

app.configure "production", ->
  app.use express.errorHandler()

app.get "/", routes.static "index"
app.get "/1/me/authored", api.mines_authored
app.get "/1/me/speaker_of", api.mines_held
app.get "/favicon.ico", express.static "#{__dirname}/public/assets/images"
app.get "/r/index.html", routes.static "index"
app.get "/r/tos.html", routes.static "tos"
app.get "/r/talks.html", routes.list_catalogs
app.get "/p.html", redirect_routes.redirect_to_presentation_from_p_html
#app.get "/m/*.:whatever?", routes.ensure_is_logged
app.get "/m/manage", routes.static "m/index"
app.get "/:catalog_name/p.html", redirect_routes.redirect_to_presentation_from_p_html
app.get "/:catalog_name/catalog.html", routes.show_catalog
app.get "/:catalog_name/catalog", routes.show_catalog
app.get "/:catalog_name/index.html", routes.show_catalog
app.get "/:catalog_name/:presentation.html", redirect_routes.redirect_to_presentation_from_html
app.get "/:catalog_name/:presentation.json", routes.raw_presentation
app.get "/:catalog_name/:presentation", routes.show_presentation
app.get "/:catalog_name", routes.show_catalog

app.listen 3000
console.log "Express server listening on port 3000 in %s mode", app.settings.env

require "./subdomain"