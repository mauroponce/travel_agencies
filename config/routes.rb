Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check
  get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  root "landing#show"
  post "/auth/google_oauth2/callback", to: "sessions#create"
  get "/auth/google_oauth2/callback", to: "sessions#create"
  get "/auth/failure", to: "sessions#failure"
  delete "/session", to: "sessions#destroy", as: :session
  get "/test/sign-in", to: "sessions#test_sign_in" if Rails.env.test?

  resource :onboarding, only: %i[show create]
  post "/context", to: "contexts#update", as: :context
  get "/dashboard", to: "dashboard#show", as: :dashboard

  resources :travel_packages, path: "paquetes"
  resources :departures, path: "salidas" do
    member { get :operation }
    resource :manifest, only: :show
    resources :boarding_events, only: :create do
      collection { post :sync }
    end
  end
  resources :departure_offers, path: "ofertas", only: %i[index show new create edit update] do
    member do
      post :publish
      post :unpublish
    end
    resources :fare_versions, path: "tarifas", only: :create
  end
  resources :reservations, path: "reservas", only: %i[index show new create] do
    member { post :cancel }
  end
  resources :passenger_forms, path: "solicitudes", only: %i[index show create] do
    member { post :convert }
  end
  resources :customer_payments, path: "pagos", only: %i[index create]
  resources :remittances, path: "rendiciones", only: %i[index create show] do
    member { post :verify }
  end
  resources :notifications, path: "notificaciones", only: %i[index update] do
    collection { post :read_all }
  end
  resources :push_subscriptions, only: %i[create destroy]
  resource :catalog, path: "catalogos", only: %i[show create destroy]
  resources :team_members, path: "equipo", only: %i[index create update]
  resources :commissions, path: "comisiones", only: :index

  namespace :platform do
    resources :companies, only: %i[index new create]
  end

  get "/viajes/:company_slug/:offer_slug", to: "public_trips#show", as: :public_trip
  get "/viajes/:company_slug/:offer_slug/status", to: "public_trips#status", as: :public_trip_status
  get "/formularios/:token", to: "public_passenger_forms#show", as: :public_passenger_form
  post "/formularios/:token", to: "public_passenger_forms#create"
end
