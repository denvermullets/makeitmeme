Rails.application.routes.draw do
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  mount ActiveStorageDB::Engine => '/active_storage_db'

  get 'up' => 'rails/health#show', as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  namespace :admin do
    get 'sign_in' => 'sessions#new'
    post 'sign_in' => 'sessions#create'
    delete 'sign_out' => 'sessions#destroy'
    resources :packs, only: %i[index create update destroy]
    resources :games, only: :index
    root 'homes#show'
    resources :templates, only: %i[update destroy] do
      post :review, on: :member
      resource :hiding, only: %i[create destroy]
      resource :text_boxes, only: :update
    end
  end

  get 'recap/:token' => 'recaps#show', as: :recap

  root 'rooms#new'
  resources :rooms, only: :create
  resources :joins, only: :create
  get 'rooms/:code' => 'rooms#show', as: :room
  post 'rooms/:code/start' => 'starts#create', as: :start_room
  post 'rooms/:code/packs/:pack_id/toggle' => 'pack_toggles#create', as: :toggle_room_pack
  post 'rooms/:code/captioning_preset' => 'captioning_presets#create', as: :room_captioning_preset
  post 'rooms/:code/players/:player_id/kick' => 'kicks#create', as: :kick_room_player
  post 'rooms/:code/leave' => 'leaves#create', as: :leave_room
  post 'rooms/:code/memes' => 'memes#create', as: :room_memes
  post 'rooms/:code/votes' => 'votes#create', as: :room_votes
  post 'rooms/:code/play_again' => 'play_agains#create', as: :play_again_room
end
