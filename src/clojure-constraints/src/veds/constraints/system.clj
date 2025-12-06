(ns veds.constraints.system
  "System configuration and lifecycle management"
  (:require [integrant.core :as ig]
            [aero.core :as aero]
            [clojure.java.io :as io]
            [clojure.tools.logging :as log]
            [veds.constraints.xtdb :as xtdb]
            [veds.constraints.redis :as redis]
            [veds.constraints.http :as http]
            [veds.constraints.sync :as sync]))

(defn load-config
  "Load configuration from resources/config.edn"
  []
  (-> (io/resource "config.edn")
      (aero/read-config {:profile (keyword (System/getenv "VEDS_ENV" "dev"))})
      (assoc-in [:ig/system] true)))

;; XTDB Node
(defmethod ig/init-key :veds/xtdb [_ config]
  (log/info "Initializing XTDB connection" config)
  (xtdb/connect config))

(defmethod ig/halt-key! :veds/xtdb [_ node]
  (log/info "Closing XTDB connection")
  (xtdb/close node))

;; Redis/Dragonfly Connection
(defmethod ig/init-key :veds/redis [_ config]
  (log/info "Initializing Redis/Dragonfly connection" config)
  (redis/connect config))

(defmethod ig/halt-key! :veds/redis [_ conn]
  (log/info "Closing Redis connection")
  (redis/close conn))

;; HTTP Server
(defmethod ig/init-key :veds/http [_ {:keys [port handler]}]
  (log/info "Starting HTTP server on port" port)
  (http/start-server handler port))

(defmethod ig/halt-key! :veds/http [_ server]
  (log/info "Stopping HTTP server")
  (http/stop-server server))

;; Constraint Sync Worker
(defmethod ig/init-key :veds/sync-worker [_ {:keys [xtdb redis interval-ms]}]
  (log/info "Starting constraint sync worker, interval:" interval-ms "ms")
  (sync/start-worker xtdb redis interval-ms))

(defmethod ig/halt-key! :veds/sync-worker [_ worker]
  (log/info "Stopping sync worker")
  (sync/stop-worker worker))
