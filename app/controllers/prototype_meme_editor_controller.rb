# PROTOTYPE (MEME-5), throwaway. Do not merge to main.
# Three Meme editor variants on one route, switched with ?variant=A|B|C.
# Templates hotlink memegen images (they send ACAO: *) so the canvas stays untainted.
class PrototypeMemeEditorController < ApplicationController
  def show
    top_bottom = [b(0, 0, 1, 0.2), b(0, 0.8, 1, 0.2)]
    @hand = [
      { id: 'drake', name: 'Drake Hotline Bling', boxes: top_bottom },
      { id: 'db', name: 'Distracted Boyfriend',
        boxes: [b(0.12, 0.7, 0.325, 0.1), b(0.55, 0.45, 0.175, 0.1), b(0.74, 0.66, 0.2, 0.1)] },
      { id: 'buzz', name: 'X, X Everywhere', boxes: top_bottom },
      { id: 'cmm', name: 'Change My Mind',
        boxes: [b(0.351, 0.434, 0.46, 0.25, angle: 23, color: 'black', font: 'thin')] },
      { id: 'ds', name: 'Daily Struggle',
        boxes: [b(0.097, 0.108, 0.32, 0.095, angle: 12.5, color: 'black', font: 'thin'), b(0.467, 0.069, 0.23, 0.09, angle: 10.5, color: 'black', font: 'thin'), b(0.04, 0.82, 0.92, 0.15)] },
      { id: 'exit', name: 'Left Exit 12 Off Ramp',
        boxes: [b(0.24, 0.15, 0.15, 0.22, font: 'thin'), b(0.53, 0.15, 0.22, 0.22, font: 'thin'), b(0.466, 0.879, 0.32, 0.1, angle: 9)] },
      { id: 'fine', name: 'This is Fine', boxes: top_bottom },
      { id: 'gru', name: "Gru's Plan",
        boxes: [b(0.275, 0.2, 0.2075, 0.2, color: 'black', font: 'thin'), b(0.78, 0.2, 0.205, 0.2, color: 'black', font: 'thin'), b(0.28, 0.7, 0.205, 0.2, color: 'black', font: 'thin'), b(0.78, 0.7, 0.205, 0.2, color: 'black', font: 'thin')] },
      { id: 'pigeon', name: 'Is This a Pigeon?',
        boxes: [b(0.15, 0, 0.35, 0.2), b(0.71, 0.3, 0.175, 0.1), b(0, 0.8, 1, 0.2)] },
      { id: 'rollsafe', name: 'Roll Safe', boxes: top_bottom }
    ].map { |t| t.merge(url: "https://api.memegen.link/images/#{t[:id]}.jpg") }
    @variant = %w[A B C].include?(params[:variant]) ? params[:variant] : 'A'
    @seconds = (params[:seconds] || 90).to_i
  end

  private

  def b(x, y, w, h, angle: 0, color: 'white', font: 'thick')
    { x: x, y: y, w: w, h: h, angle: angle, color: color, font: font }
  end
end
