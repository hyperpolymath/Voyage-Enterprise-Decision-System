(ns veds.datalog.compiler
  "Compile constraint DSL to Datalog rules"
  (:require [clojure.walk :as walk]))

(defn substitute-params
  "Substitute parameter placeholders in a Datalog rule"
  [rule params]
  (walk/postwalk
   (fn [form]
     (if (and (symbol? form)
              (= \? (first (name form))))
       (let [param-name (keyword (subs (name form) 1))]
         (get params param-name form))
       form))
   rule))

(defn compile-rule
  "Compile a Datalog rule template with parameters"
  [rule-template params]
  (substitute-params rule-template params))

;; =============================================================================
;; DSL Parser
;; =============================================================================

(defn parse-constraint-dsl
  "Parse a human-readable constraint DSL into Datalog

  Example:
    'For all segments where country = DE, wage >= 1260 cents/hour'
  "
  [dsl-string]
  ;; Simplified parser - real implementation would be more robust
  (let [tokens (clojure.string/split dsl-string #"\s+")]
    (cond
      ;; Wage constraint pattern
      (and (some #{"wage"} tokens)
           (some #{">=" ">"} tokens))
      (let [country (second (drop-while #(not= % "country") tokens))
            min-wage (Integer/parseInt (last (filter #(re-matches #"\d+" %) tokens)))]
        {:constraint-type :wage-minimum
         :params {:country country
                  :min-wage-cents min-wage}
         :datalog-rule
         '[:find ?segment ?violation
           :in $ ?route-id
           :where
           [?route :route/id ?route-id]
           [?route :route/segments ?segment]
           [?segment :segment/country ?country]
           [?segment :segment/wage-cents ?wage]
           [(< ?wage ?min-wage)]
           [(identity ?segment) ?violation]]})

      ;; Carbon constraint pattern
      (some #{"carbon"} tokens)
      (let [budget (Double/parseDouble (last (filter #(re-matches #"\d+\.?\d*" %) tokens)))]
        {:constraint-type :carbon-budget
         :params {:budget-kg budget}
         :datalog-rule
         '[:find ?route ?carbon
           :in $ ?route-id ?budget
           :where
           [?route :route/id ?route-id]
           [?route :route/total-carbon-kg ?carbon]
           [(> ?carbon ?budget)]]})

      ;; Time constraint pattern
      (some #{"time" "hours" "deadline"} tokens)
      (let [hours (Double/parseDouble (last (filter #(re-matches #"\d+\.?\d*" %) tokens)))]
        {:constraint-type :time-window
         :params {:max-hours hours}
         :datalog-rule
         '[:find ?route ?time
           :in $ ?route-id ?max-hours
           :where
           [?route :route/id ?route-id]
           [?route :route/total-time-hours ?time]
           [(> ?time ?max-hours)]]})

      :else
      {:constraint-type :custom
       :params {}
       :datalog-rule nil
       :raw-dsl dsl-string})))

;; =============================================================================
;; Constraint Templates
;; =============================================================================

(def templates
  "Pre-defined constraint templates"
  {:ilo-minimum-wage
   {:name "ILO Minimum Wage"
    :description "Ensure all carriers pay at least the ILO-specified minimum wage"
    :constraint-type :wage-minimum
    :hard? true
    :datalog-rule
    '[:find ?segment ?country ?wage ?min-wage
      :in $ ?route-id
      :where
      [?route :route/id ?route-id]
      [?route :route/segments ?segment]
      [?segment :segment/country ?country]
      [?segment :segment/wage-cents ?wage]
      [?c :country/code ?country]
      [?c :country/min-wage-cents ?min-wage]
      [(< ?wage ?min-wage)]]}

   :eu-working-time-directive
   {:name "EU Working Time Directive"
    :description "Maximum 48 hours per week for EU segments"
    :constraint-type :hours
    :hard? true
    :params {:region "EU" :max-hours 48}}

   :carbon-neutral-2030
   {:name "Carbon Neutral 2030 Target"
    :description "Carbon budget aligned with 2030 neutrality goals"
    :constraint-type :carbon-budget
    :hard? false
    :params {:budget-kg-per-tonne-km 0.05}}

   :ofac-sanctions
   {:name "OFAC Sanctions Compliance"
    :description "No sanctioned carriers or routes"
    :constraint-type :sanction
    :hard? true}})

(defn instantiate-template
  "Create a constraint from a template with custom parameters"
  [template-key custom-params]
  (when-let [template (get templates template-key)]
    (-> template
        (update :params merge custom-params)
        (assoc :constraint-id (str (name template-key) "-" (System/currentTimeMillis))))))
