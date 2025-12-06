(ns veds.constraints.core
  "Core constraint definitions and evaluation"
  (:require [clojure.spec.alpha :as s]
            [clojure.tools.logging :as log]
            [veds.constraints.xtdb :as xtdb]
            [veds.datalog.compiler :as compiler]))

;; =============================================================================
;; Constraint Specs
;; =============================================================================

(s/def ::constraint-id string?)
(s/def ::constraint-type #{:wage :carbon :time :cost :sanction :hours :custom})
(s/def ::name string?)
(s/def ::description string?)
(s/def ::hard? boolean?)
(s/def ::active? boolean?)
(s/def ::params map?)
(s/def ::datalog-rule vector?)

(s/def ::constraint
  (s/keys :req-un [::constraint-id ::constraint-type ::name ::hard?]
          :opt-un [::description ::params ::datalog-rule ::active?]))

;; =============================================================================
;; Built-in Constraint Types
;; =============================================================================

(def constraint-templates
  "Templates for common constraint types"
  {:wage-minimum
   {:description "Ensure wage meets country minimum"
    :hard? true
    :datalog-template
    '[:find ?segment ?violation
      :in $ ?route-id ?min-wage
      :where
      [?route :route/id ?route-id]
      [?route :route/segments ?segment]
      [?segment :segment/wage-cents ?wage]
      [(< ?wage ?min-wage)]
      [(identity ?segment) ?violation]]}

   :carbon-budget
   {:description "Total carbon must be under budget"
    :hard? false
    :datalog-template
    '[:find ?route ?total-carbon
      :in $ ?route-id ?budget
      :where
      [?route :route/id ?route-id]
      [?route :route/total-carbon-kg ?total-carbon]
      [(> ?total-carbon ?budget)]]}

   :time-window
   {:description "Delivery must be within time window"
    :hard? true
    :datalog-template
    '[:find ?route ?delivery-time
      :in $ ?route-id ?deadline
      :where
      [?route :route/id ?route-id]
      [?route :route/arrival-time ?delivery-time]
      [(> ?delivery-time ?deadline)]]}

   :sanctioned-carrier
   {:description "No sanctioned carriers allowed"
    :hard? true
    :datalog-template
    '[:find ?segment ?carrier
      :in $ ?route-id ?sanctioned-carriers
      :where
      [?route :route/id ?route-id]
      [?route :route/segments ?segment]
      [?segment :segment/carrier-code ?carrier]
      [(contains? ?sanctioned-carriers ?carrier)]]}})

;; =============================================================================
;; Constraint CRUD
;; =============================================================================

(defn create-constraint
  "Create a new constraint definition"
  [xtdb-node constraint]
  {:pre [(s/valid? ::constraint constraint)]}
  (let [id (or (:constraint-id constraint) (str (java.util.UUID/randomUUID)))
        doc (merge {:xt/id (keyword "constraint" id)
                    :constraint/id id
                    :constraint/active? true
                    :constraint/created-at (java.time.Instant/now)}
                   (select-keys constraint
                                [:constraint-type :name :description
                                 :hard? :params :datalog-rule]))]
    (xtdb/submit! xtdb-node [[:xtdb.api/put doc]])
    (log/info "Created constraint" id)
    doc))

(defn get-constraint
  "Get a constraint by ID"
  [xtdb-node constraint-id]
  (xtdb/entity xtdb-node (keyword "constraint" constraint-id)))

(defn list-constraints
  "List all active constraints"
  [xtdb-node]
  (xtdb/q xtdb-node
          '{:find [(pull ?c [*])]
            :where [[?c :constraint/id _]
                    [?c :constraint/active? true]]}))

(defn update-constraint
  "Update a constraint (creates new version in XTDB)"
  [xtdb-node constraint-id updates]
  (when-let [existing (get-constraint xtdb-node constraint-id)]
    (let [updated (merge existing
                         updates
                         {:constraint/updated-at (java.time.Instant/now)})]
      (xtdb/submit! xtdb-node [[:xtdb.api/put updated]])
      (log/info "Updated constraint" constraint-id)
      updated)))

(defn deactivate-constraint
  "Soft-delete a constraint"
  [xtdb-node constraint-id]
  (update-constraint xtdb-node constraint-id {:constraint/active? false}))

;; =============================================================================
;; Constraint Evaluation
;; =============================================================================

(defn evaluate-constraint
  "Evaluate a single constraint against a route"
  [xtdb-node constraint route]
  (let [constraint-id (:constraint/id constraint)
        datalog-rule (:constraint/datalog-rule constraint)
        params (:constraint/params constraint)
        route-id (:route/id route)]
    (if datalog-rule
      (let [violations (xtdb/q xtdb-node
                               (compiler/compile-rule datalog-rule params)
                               route-id)]
        {:constraint-id constraint-id
         :constraint-type (:constraint/constraint-type constraint)
         :passed? (empty? violations)
         :hard? (:constraint/hard? constraint)
         :violations (vec violations)
         :score (if (empty? violations) 1.0 0.0)})
      ;; No datalog rule - use default evaluation
      {:constraint-id constraint-id
       :constraint-type (:constraint/constraint-type constraint)
       :passed? true
       :hard? (:constraint/hard? constraint)
       :violations []
       :score 1.0})))

(defn evaluate-route
  "Evaluate all active constraints against a route"
  [xtdb-node route]
  (let [constraints (list-constraints xtdb-node)]
    (mapv #(evaluate-constraint xtdb-node % route) constraints)))

(defn all-hard-constraints-passed?
  "Check if all hard constraints passed"
  [evaluation-results]
  (every? (fn [r]
            (or (not (:hard? r))
                (:passed? r)))
          evaluation-results))

(defn overall-score
  "Calculate overall constraint satisfaction score"
  [evaluation-results]
  (if (empty? evaluation-results)
    1.0
    (/ (reduce + (map :score evaluation-results))
       (count evaluation-results))))
