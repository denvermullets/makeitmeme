# Meme Game

A live party game: players in a private room caption meme images, vote on each other's work, and are scored over three rounds.

## Language

### Playing together

**Room**:
A private, live space that Players enter with a join code, where one Game after another is played.
_Avoid_: Lobby, match, session

**Player**:
A person taking part in a Room, identified only by their nickname within that Room; no account.
_Avoid_: User, participant, member

**Host**:
The Player who created the Room.
_Avoid_: Owner, leader

**Away**:
A Player whose browser has been out of touch with the Room for a short while; they stay in the Room and the Game, and become present again as soon as they're back.
_Avoid_: Disconnected, offline, left, gone

**Spectator**:
A Player who arrived mid-Game and sits it out until the next Game; they watch but don't vote and aren't scored.
_Avoid_: Waiting Player, bench, observer

**Admin**:
The operator of the site who curates the Template Library; not a Player role.
_Avoid_: Moderator, host, superuser

### Templates

**Template**:
A meme image with one or more Text Boxes, which Players caption.
_Avoid_: Image, picture, base, background

**Text Box**:
A predefined region on a Template where caption text goes; text shrinks to fit inside it.
_Avoid_: Caption slot, text area, field

**Template Library**:
The single shared, persistent collection of every Template, whether uploaded by Players or curated by the Admin.
_Avoid_: Pool, catalog, deck

**Pack**:
A themed group of Templates within the Template Library; every Template belongs to exactly one, and a Room deals only from the Packs its Host turns on.
_Avoid_: Theme, category, collection, set

**Custom Pack**:
The Pack that every Player-uploaded Template joins.
_Avoid_: User pack, uploads

**Upload page**:
The one page where a Player uploads a picture and edits it into a Template; reached from the home screen (and, between Games, from a Room). Never available during a Round.
_Avoid_: Uploader, upload form

**Upload draft**:
A Player's unfinished upload: the picture and its Text Boxes, owned by one browser and not yet in the Template Library, so it is never dealt. Adding it to the library turns it into a Template in the Custom Pack; abandoned drafts are cleaned up.
_Avoid_: Pending Template, unpublished Template

**Hide from Hands**:
An Admin action that keeps a Template in the Template Library but stops it being dealt into any new Hand; Hands already dealt are untouched, and the Admin can undo it.
_Avoid_: Disable, archive, soft delete, ban

**Mark reviewed**:
An Admin action that records the Admin has checked a Template's Text Boxes; saving the Text Boxes marks it reviewed too, but renaming or moving it does not.
_Avoid_: Approve, publish, verify

### Gameplay

**Game**:
One run of three Rounds within a Room, ending in the Scoreboard; scores and Buddies belong to a Game.
_Avoid_: Match, session, playthrough

**Round**:
One cycle of captioning, voting, and scoring within a Game; a Game has three.
_Avoid_: Turn, stage, level

**Hand**:
The ten Templates dealt to one Player in a Round, from which they choose one to caption.
_Avoid_: Options, choices, deck

**Meme**:
A Template with a Player's caption text baked in, submitted for a Round.
_Avoid_: Submission, entry, caption, post

**Vote**:
One Player's verdict on another Player's Meme: up, meh, or down.
_Avoid_: Rating, score, reaction

**Buddy**:
A limited token a Player spends instead of an up Vote to mark a Meme as exceptional, worth more points.
_Avoid_: Meme Buddy, super-vote, boost, star

**Meme of the Round**:
The highest-scoring Meme of a Round, highlighted for honour only; ties share the title.
_Avoid_: Winner, best meme, MVP

**Captioning preset**:
How long Captioning lasts: Quick 60s, Normal 90s (the default) or Chill 150s. The Host chooses it in Waiting or on the Scoreboard; it is stored on the Room, so it carries through Play again.
_Avoid_: Timer, difficulty, speed

**Standings**:
Every Player's running total shown between Rounds, before the Game has ended.
_Avoid_: Scoreboard (that is the final one), leaderboard

**Scoreboard**:
The final standings of every Player once a Game's third Round ends.
_Avoid_: Leaderboard, results, rankings

**Recap**:
The permanent, shareable page of one finished Game: its Scoreboard and every Meme, viewable by anyone with its link.
_Avoid_: Archive, history, results
