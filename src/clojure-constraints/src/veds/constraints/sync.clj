(ns veds.constraints.sync
  "Synchronize constraints from XTDB to Dragonfly for hot path evaluation"
  (:require [clojure.tools.logging :as log]
            [clojure.core.async :as async :refer [go-loop <! timeout]]
            [veds.constraints.core :as core]
            [veds.constraints.redis :as redis]
            [jsonista.core :as json]))

(def ^:private json-mapper
  (json/object-mapper {:encode-key-fn name
                       :decode-key-fn keyword}))

(defn compile-constraint-to-lookup
  "Compile a constraint into a fast lookup format for Dragonfly"
  [constraint]
  (let [ctype (:constraint/constraint-type constraint)
        params (:constraint/params constraint)]
    (case ctype
      :wage-minimum
      {:type :hash
       :key (str "constraint:min_wage:" (:country params))
       :value (str (:min-wage-cents params))}

      :carbon-budget
      {:type :string
       :key "constraint:carbon_budget:default"
       :value (str (:budget-kg params))}

      :sanctioned-carrier
      {:type :set
       :key "constraint:sanctioned:carriers"
       :values (:carriers params)}

      :hours-maximum
      {:type :hash
       :key (str "constraint:max_hours:" (:region params))
       :value (str (:max-hours params))}

      ;; Default: store as JSON
      {:type :string
       :key (str "constraint:custom:" (:constraint/id constraint))
       :value (json/write-value-as-string constraint json-mapper)})))

(defn sync-constraints-to-redis!
  "Sync all active constraints to Redis/Dragonfly"
  [xtdb-node redis-conn]
  (log/debug "Syncing constraints to Dragonfly")
  (let [constraints (core/list-constraints xtdb-node)
        lookups (mapv compile-constraint-to-lookup (map first constraints))]

    ;; Clear existing constraints (atomic update)
    (redis/execute redis-conn
                   ["DEL"
                    "constraint:min_wage:*"
                    "constraint:max_hours:*"
                    "constraint:sanctioned:carriers"
                    "constraint:carbon_budget:*"])

    ;; Write new constraints
    (doseq [lookup lookups]
      (case (:type lookup)
        :string
        (redis/execute redis-conn ["SET" (:key lookup) (:value lookup)])

        :hash
        (redis/execute redis-conn ["SET" (:key lookup) (:value lookup)])

        :set
        (when (seq (:values lookup))
          (apply redis/execute
                 redis-conn
                 (into ["SADD" (:key lookup)] (:values lookup))))

        nil))

    ;; Publish sync complete event
    (redis/execute redis-conn
                   ["PUBLISH" "constraint:sync" (str (System/currentTimeMillis))])

    (log/info "Synced" (count lookups) "constraints to Dragonfly")))

;; =============================================================================
;; Sync Worker
;; =============================================================================

(defn start-worker
  "Start a background worker that syncs constraints periodically"
  [xtdb-node redis-conn interval-ms]
  (let [running (atom true)
        worker-chan (async/chan)]

    ;; Initial sync
    (try
      (sync-constraints-to-redis! xtdb-node redis-conn)
      (catch Exception e
        (log/error e "Initial constraint sync failed")))

    ;; Periodic sync loop
    (go-loop []
      (when @running
        (<! (timeout interval-ms))
        (try
          (sync-constraints-to-redis! xtdb-node redis-conn)
          (catch Exception e
            (log/error e "Constraint sync failed")))
        (recur)))

    {:running running
     :channel worker-chan}))

(defn stop-worker
  "Stop the sync worker"
  [worker]
  (reset! (:running worker) false)
  (async/close! (:channel worker)))
