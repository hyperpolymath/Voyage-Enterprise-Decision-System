(ns veds.constraints.http
  "HTTP API for constraint management"
  (:require [reitit.ring :as ring]
            [reitit.coercion.spec]
            [reitit.ring.coercion :as coercion]
            [reitit.ring.middleware.muuntaja :as muuntaja]
            [reitit.ring.middleware.parameters :as parameters]
            [muuntaja.core :as m]
            [ring.adapter.jetty :as jetty]
            [clojure.tools.logging :as log]
            [veds.constraints.core :as core]))

(defn make-handler
  "Create the HTTP handler with all routes"
  [xtdb-node redis-conn]
  (ring/ring-handler
   (ring/router
    [["/health"
      {:get {:handler (fn [_]
                        {:status 200
                         :body {:status "ok"
                                :service "veds-constraints"}})}}]

     ["/api/v1"
      ["/constraints"
       {:get {:summary "List all constraints"
              :handler (fn [_]
                         {:status 200
                          :body {:data (core/list-constraints xtdb-node)}})}
        :post {:summary "Create a constraint"
               :handler (fn [{:keys [body-params]}]
                          (let [constraint (core/create-constraint xtdb-node body-params)]
                            {:status 201
                             :body {:data constraint}}))}}]

      ["/constraints/:id"
       {:get {:summary "Get a constraint"
              :handler (fn [{{:keys [id]} :path-params}]
                         (if-let [constraint (core/get-constraint xtdb-node id)]
                           {:status 200
                            :body {:data constraint}}
                           {:status 404
                            :body {:error "Constraint not found"}}))}
        :put {:summary "Update a constraint"
              :handler (fn [{{:keys [id]} :path-params
                            body :body-params}]
                         (if-let [updated (core/update-constraint xtdb-node id body)]
                           {:status 200
                            :body {:data updated}}
                           {:status 404
                            :body {:error "Constraint not found"}}))}
        :delete {:summary "Delete a constraint"
                 :handler (fn [{{:keys [id]} :path-params}]
                            (core/deactivate-constraint xtdb-node id)
                            {:status 204})}}]

      ["/constraints/evaluate"
       {:post {:summary "Evaluate constraints for a route"
               :handler (fn [{:keys [body-params]}]
                          (let [route (:route body-params)
                                results (core/evaluate-route xtdb-node route)]
                            {:status 200
                             :body {:data results
                                    :all-hard-passed (core/all-hard-constraints-passed? results)
                                    :overall-score (core/overall-score results)}}))}}]

      ["/sync"
       {:post {:summary "Trigger constraint sync to Dragonfly"
               :handler (fn [_]
                          (require '[veds.constraints.sync :as sync])
                          ((resolve 'sync/sync-constraints-to-redis!) xtdb-node redis-conn)
                          {:status 200
                           :body {:status "synced"}})}}]]]

    {:data {:coercion reitit.coercion.spec/coercion
            :muuntaja m/instance
            :middleware [parameters/parameters-middleware
                         muuntaja/format-negotiate-middleware
                         muuntaja/format-response-middleware
                         muuntaja/format-request-middleware
                         coercion/coerce-response-middleware
                         coercion/coerce-request-middleware]}})

   (ring/create-default-handler
    {:not-found (constantly {:status 404 :body {:error "Not found"}})})))

(defn start-server
  "Start the HTTP server"
  [handler port]
  (jetty/run-jetty handler
                   {:port port
                    :join? false}))

(defn stop-server
  "Stop the HTTP server"
  [server]
  (.stop server))
