(ns veds.constraints.redis
  "Redis/Dragonfly client wrapper using Carmine"
  (:require [taoensso.carmine :as car :refer [wcar]]
            [clojure.tools.logging :as log]))

(defn connect
  "Create Redis connection pool"
  [{:keys [host port password]}]
  (log/info "Connecting to Redis/Dragonfly at" host ":" port)
  {:pool {}
   :spec {:host host
          :port port
          :password password}})

(defn close
  "Close Redis connection"
  [conn]
  (log/info "Closed Redis connection"))

(defmacro with-conn
  "Execute commands with connection"
  [conn & body]
  `(wcar (:spec ~conn) ~@body))

(defn execute
  "Execute a Redis command"
  [conn cmd]
  (wcar (:spec conn)
        (apply car/redis-call cmd)))

(defn get-key
  "Get a key value"
  [conn key]
  (wcar (:spec conn)
        (car/get key)))

(defn set-key
  "Set a key value"
  [conn key value & {:keys [ex px]}]
  (wcar (:spec conn)
        (if ex
          (car/setex key ex value)
          (if px
            (car/psetex key px value)
            (car/set key value)))))

(defn get-set-members
  "Get all members of a set"
  [conn key]
  (wcar (:spec conn)
        (car/smembers key)))

(defn add-to-set
  "Add values to a set"
  [conn key & values]
  (wcar (:spec conn)
        (apply car/sadd key values)))

(defn publish
  "Publish a message to a channel"
  [conn channel message]
  (wcar (:spec conn)
        (car/publish channel message)))

(defn subscribe
  "Subscribe to channels"
  [conn channels handler]
  (car/with-new-pubsub-listener (:spec conn)
    (zipmap channels (repeat handler))
    (apply car/subscribe channels)))
