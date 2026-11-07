Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  mount ActiveStorageDB::Engine => '/active_storage_db'

  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # PROTOTYPE (MEME-5), throwaway: Meme editor variants, dev only.
  get 'prototype/meme_editor' => 'prototype_meme_editor#show' if Rails.env.development?
  # PROTOTYPE (MEME-6), throwaway: Admin Text Box editor variants, dev only.
  get 'prototype/admin_text_boxes' => 'prototype_admin_text_boxes#show' if Rails.env.development?

  root 'rooms#new'
  resources :rooms, only: :create
  resources :joins, only: :create
  get 'rooms/:code' => 'rooms#show', as: :room
  post 'rooms/:code/start' => 'starts#create', as: :start_room
end
