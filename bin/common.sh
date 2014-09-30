error() {
  echo " !     $*" >&2
  exit 1
}

say() {
  echo "-----> $*"
}

protip() {
  echo
  echo "PRO TIP: $*" | indent
  echo
}

# sed -l basically makes sed replace and buffer through stdin to stdout
# so you get updates while the command runs and dont wait for the end
# e.g. npm install | indent
indent() {
  c='s/^/       /'
  case $(uname) in
    Darwin) sed -l "$c";; # mac/bsd sed: -l buffers on line boundaries
    *)      sed -u "$c";; # unix/gnu sed: -u unbuffered (arbitrary) chunks of data
  esac
}

resolve_nginx_version() {
  echo $(curl --silent --get --data-urlencode "range=$1" https://semver.io/nginx/resolve)
}

add_nginx_mantainers_pgp_keys() {
  curl http://nginx.org/keys/aalexeev.key -s | gpg --import - && \
  curl http://nginx.org/keys/is.key       -s | gpg --import - && \
  curl http://nginx.org/keys/mdounin.key  -s | gpg --import - && \
  curl http://nginx.org/keys/maxim.key    -s | gpg --import - && \
  curl http://nginx.org/keys/sb.key       -s | gpg --import - && \
  curl http://nginx.org/keys/glebius.key  -s | gpg --import - || \
  exit 1
}

add_module_option() {
  # Check nginx modules
  local nginx_modules_arg=''
  for module in $@; do
    [[ ! -d $module ]] && continue

    # if no config file found, search inner directories
    if [[ ! -f $module/config ]]; then
      for submodule in $module/*; do
        echo $nginx_modules_arg | \grep -q $submodule && continue
        nginx_modules_arg="$nginx_modules_arg --add-module=$submodule"
      done
    else
      echo $nginx_modules_arg | \grep -q $module && continue
      nginx_modules_arg="$nginx_modules_arg --add-module=$module"
    fi
  done

  echo $nginx_modules_arg
}

verify_gpg() {
  gpg --verify $1 || exit 1
}

export_env_dir() {
  env_dir=$1
  whitelist_regex=${2:-''}
  blacklist_regex=${3:-'^(PATH|GIT_DIR|CPATH|CPPATH|LD_PRELOAD|LIBRARY_PATH)$'}
  if [ -d "$env_dir" ]; then
    for e in $(ls $env_dir); do
      echo "$e" | grep -E "$whitelist_regex" | grep -qvE "$blacklist_regex" &&
      export "$e=$(cat $env_dir/$e)"
      :
    done
  fi
}
