# PROTOTYPE (MEME-6), throwaway. Do not merge to main.
# Three Admin Text Box editor variants on one route, switched with ?variant=A|B|C.
# Nothing persists: the Template Library below is reloaded on every request; edits live in browser memory.
# Templates hotlink memegen images (they send ACAO: *) so the canvas stays untainted.
class PrototypeAdminTextBoxesController < ApplicationController
  def show
    tb = [b(0, 0, 1, 0.2), b(0, 0.8, 1, 0.2)]
    @templates = [
      # Imported with memegen's generic top/bottom strips; the text really belongs on the right half.
      t('drake', 'Drake Hotline Bling', tb, uses: 14),
      t('db', 'Distracted Boyfriend',
        [b(0.12, 0.7, 0.325, 0.1), b(0.55, 0.45, 0.175, 0.1), b(0.74, 0.66, 0.2, 0.1)], reviewed: true, uses: 22),
      t('cmm', 'Change My Mind', [b(0.351, 0.434, 0.46, 0.25, angle: 23, color: 'black', font: 'thin')],
        reviewed: true, uses: 9),
      t('gru', "Gru's Plan",
        [b(0.275, 0.2, 0.2075, 0.2, color: 'black', font: 'thin'), b(0.78, 0.2, 0.205, 0.2, color: 'black', font: 'thin'),
         b(0.28, 0.7, 0.205, 0.2, color: 'black', font: 'thin'), b(0.78, 0.7, 0.205, 0.2, color: 'black', font: 'thin')],
        reviewed: true, uses: 11),
      t('fry', 'Not Sure If', tb, source: 'Uploaded by Priya in Room KXQ4', uses: 0),
      t('pigeon', 'Is This a Pigeon?', [b(0.15, 0, 0.35, 0.2), b(0.71, 0.3, 0.175, 0.1), b(0, 0.8, 1, 0.2)], uses: 5),
      t('exit', 'Left Exit 12 Off Ramp',
        [b(0.24, 0.15, 0.15, 0.22, font: 'thin'), b(0.53, 0.15, 0.22, 0.22, font: 'thin'), b(0.466, 0.879, 0.32, 0.1, angle: 9)],
        reviewed: true, uses: 7),
      t('success', 'Success Kid', tb, source: 'Uploaded by Sam in Room PLMB', uses: 1),
      t('buzz', 'X, X Everywhere', tb, uses: 3),
      t('fine', 'This is Fine', tb, uses: 18),
      t('kermit', "But That's None of My Business", tb, uses: 2),
      t('rollsafe', 'Roll Safe', tb, hidden: true, uses: 4),
      t('ds', 'Daily Struggle',
        [b(0.097, 0.108, 0.32, 0.095, angle: 12.5, color: 'black', font: 'thin'),
         b(0.467, 0.069, 0.23, 0.09, angle: 10.5, color: 'black', font: 'thin'), b(0.04, 0.82, 0.92, 0.15)],
        reviewed: true, uses: 6)
    ]
    @variant = %w[A B C].include?(params[:variant]) ? params[:variant] : 'A'
  end

  private

  def t(id, name, boxes, source: 'memegen import', reviewed: false, hidden: false, uses: 0)
    { id: id, name: name, url: "https://api.memegen.link/images/#{id}.jpg", boxes: boxes,
      source: source, reviewed: reviewed, hidden: hidden, uses: uses }
  end

  # Text Box: x/y = top-left, w/h = size, all 0-1 fractions of the image; angle in degrees about the box centre.
  def b(x, y, w, h, angle: 0, color: 'white', font: 'thick')
    { x: x, y: y, w: w, h: h, angle: angle, color: color, font: font }
  end
end
