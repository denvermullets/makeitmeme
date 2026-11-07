# Pin npm packages by running ./bin/importmap

pin 'application'
pin '@hotwired/turbo-rails', to: 'turbo.min.js'
pin '@hotwired/stimulus', to: 'stimulus.min.js'
pin '@hotwired/stimulus-loading', to: 'stimulus-loading.js'
pin 'meme_render'
pin 'meme_submit'
pin '@rails/activestorage', to: 'activestorage.esm.js'
pin_all_from 'app/javascript/controllers', under: 'controllers'
