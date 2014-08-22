Heroku buildpack for Nginx
==========================

## How it works?

* Installs the .nginx.version specified in your `nginx.json`.
* Compiles nginx with your modules from your `/modules` folder.
* Automatically recompile nginx and modules if modifications are detected.
* Caches nginx source code for faster deploy.

### Running on heroku

Since heroku controls your process under its own process model and dynos, you
need to disable daemon init style from nginx, redirect logs to stdout/stderr
and listen to a dynamic port.

This can be done setting your own `nginx.conf` at the root of your app:
```nginx
daemon off;       # Required
error_log stderr; # Optional, but high recommend

html {
  # Uncomment the line below if you want to enable custom configs from this buildpack
  # include conf.d/*.conf;
  # ...
  server {
    # ...
    access_log stdout; # Optional

    # The following annotation will replace '80' on the next line by the env var '$PORT'
    # heroku:replace_with_env:80:PORT
    listen 80;
    # ...
  }
}
```

When you start your app, the init script will:
* Read your `nginx.conf`.
* Execute all annotations.
* Save the new config file.
* Run Nginx with this config.
