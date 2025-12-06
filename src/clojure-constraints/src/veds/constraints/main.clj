(ns veds.constraints.main
  "VEDS Constraint Engine - Main Entry Point

  Provides:
  - Constraint definition and storage in XTDB
  - Datalog rule compilation
  - Constraint evaluation
  - Cache synchronization to Dragonfly"
  (:require [integrant.core :as ig]
            [clojure.tools.logging :as log]
            [veds.constraints.system :as system])
  (:gen-class))

(defn -main
  "Start the constraint engine service"
  [& _args]
  (log/info "Starting VEDS Constraint Engine")
  (let [config (system/load-config)
        system (ig/init config)]
    (.addShutdownHook
     (Runtime/getRuntime)
     (Thread. ^Runnable #(do
                           (log/info "Shutting down...")
                           (ig/halt! system))))
    (log/info "VEDS Constraint Engine started")
    @(promise))) ; Block forever
