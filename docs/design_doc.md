# "A Blue Orb" Design Doc

*Exported from `A Blue Orb.docx`, kept in sync with the source. See `architecture.md` for the technical/numbers reference derived from this doc.*

## 1. Project Overview

**Title:** Working title: "A Blue Orb"

**Genre:** Minimalist incremental / rpg / town builder / (maybe strategy game)

**Platform:** Web based - possibly standalone app one day

**ESRB:** Mild discussions of violence, war, starvation, disease, and death.

**Engine:** Godot

**Development Team:**
- Gossett: Coding, balancing
- Falkner: Design, writing, and storyboarding

**Elevator Pitch:** A Blue Orb is "A Dark Room" and "Universal Paperclips" inspired minimalist role playing game with incremental elements about trying to find your way home in a world that thinks little of you…at first.

## 2. Vision Statement

### Core Experience

- **Curiosity** - The player should be curious. As a minimalist game, very little information is provided to the player. There is no dialogue, or instructions provided.
- **Secure** - The player should never go backwards. Numbers can always go up. That may require the player to balance certain things, but the player should never reach an unrecoverable state.
- **Power Fantasy** - The player starts weak and unvalued even by the mage that accidentally summons him, but eventually builds a powerful army / base of power.

### Design Pillars

- **Expansion** - The game should start small and constantly grow in scope for the player.
- **Minimalist Visual Design** - This product is mostly text and buttons. I might make some pixel art for the game, but it might be better if I don't. I might add some audio to certain things. This would be done later likely.
- **Levity** - The game starts with some dark thoughts and might have references to things being bad in his old life, but this is a world of magic, plenty, and wonder. Each new thing starts small, but grows grand, luminous, and mystical.

## 3. High-Level Gameplay Loop

The game is mostly buttons and menus with a string of text that appears on the side of the screen, describing what is happening.

```
Explore New Mechanic or Area
   ↓
Gather Resources
   ↓
Build new ways to gather / hold new resources
   ↓
Accomplish Area Task
   ↓
Unlock New Mechanic or Area (Repeat)
```

The game should auto save relatively often so session length should not matter. Average playthrough for minimum viable product should be 3-4 hours, with a stretch goal at 6 hours.

The game will likely not be very "replayable" as there won't be branching decisions or secondary objectives to choose.

## 4. Story

### Setting

The player leaves a world of war and hunger and finds themselves in another world filled with magic where there are wizards with great power and their magical creations. The world does not care for him or place any value on his life. The non-wizard entities do not try to fight him so much as iron him out of the world like a difficult wrinkle in a clean pressed sheet.

### Premise

The player grows in power with the desire to complete the ritual and return home. (Stretch goal: the player chooses to stay and take on the wizards and rule the land.)

### Themes

Explore a journey from powerlessness and irrelevancy to being drunk on power to eventually remembering the player's roots and returning home. (Stretch: in order to lean into the drunk-on-power side, the player is tempted to waste time and resources on luxury and comfort "upgrades" that do not help in any gameplay way.)

### Main Characters

- **Player** - Nameless, faceless, genderless?
- **Blue Wizard** - Main antagonist, views the player as trivial.

### Main Plot Ideas

**Intro:** It is hard to remember a time before the war. Hunger is a constant companion. You go to search a cabinet you've already looked in before when with a blinding flash, you find yourself on a cold stone pedestal. A scowling wizard, clad in blue, looks down at you underneath a thicket of white eyebrows. "Ergh, such an unreliable spell." With an annoyed sigh, the wizard produces a round object, seemingly from nowhere. He places it in front of you, and grumbles, "take this toy, redo the ritual, and go away. It isn't worth my mana to send you back." The wizard turns as if to walk away, but with a single step and a shimmer of light, he disappears. You did not even speak before he was gone. It is too late now. You are alone. So you reach out for the object and touch…a blue orb.

**Ending 1, Charge the circles:** With the circles charged and power seemingly flowing from the pillars through the magic circles, the power needs a focus. The player must place the blue orb upon the pedestal to combine the energies and open the portal. Upon doing so the player is returned to their own time and place. The world is unchanged. The player is reunited with their family and friends who were none the wiser as to their disappearance. The player has a feeling of loss over giving up such power, but comfort in returning home to the ones they love.

## 5. Gameplay

### Player Goals

- **Short Term Goals** - Gain Resources, use those resources to purchase things to increase resource income.
- **Medium Term Goals** - Complete each Area.
- **Long Term Goals** - Charge the four pillars, complete the ritual to power the portal home.
- **(Stretch) Long Term Goal** - Go into battle with the other wizards of the land, with the goal of conquering the continent.

## 6. Mechanics - "Areas"

### The House

Initially the game is a clicker that quickly becomes an incremental (with an auto-clicker limiter). Trading life-force into the orb for mana, spending mana to create familiars, spending familiars to buy food, and furnish the house. Food is consumed to restore life force. Furnishing the house increases different things such as maximum life force, how much life force food restores, maximum familiars.

Eventually familiars can be tasked with channeling into the orb to generate Mana over time, rather than clicking and spending lifeforce. (The game will later be known as Blue Mana.)

(Stretch goal) The life force counter and the mana counter take a few clicks to show up.

(Stretch Goal) The player can choose to continue upgrading the house for a while. I think this should be able to be done way too far — like to a ridiculous amount, taking far, far longer than it should. This will level up everything including food, floor, bed, and anything we can think of. These transmutations allow the creation of more and more blue mana or actually do nothing at all — like spawning gardens and fountains. Large amounts of blue mana isn't super needed anywhere else, for any reason. This just fits into the idea of how this power can be intoxicating.

**House name progression:** Begins called "A Small Shelter," changes names a few times based on how built up the House is. Possible progression of names (in progress, we don't need to use any/all of these, many would only be used in the stretch goal):

1. A Small Shelter
2. A Lonely Hut (A Dark Room reference)
3. A Sturdy Cottage
4. A Comfortable House
5. A Fine Residence
6. A Wealthy Manor
7. A Baronial Estate
8. A Royal Fortress
9. The Crystal Palace
10. The Mythic Stronghold
11. The Heavenly Citadel
12. The Cosmic Sanctuary
13. The Undying Throne (40k reference)

At some point in upgrading the house, the "Ritual Site" tab becomes available. Maybe once the player is channeling enough mana per second. The player should also be able to start auto-summoning familiars at a cost of mana per second.

Just so we have somewhere to start, the player starts with 0 Mana, and 50 Health. If the player loses all health, fade to black and put all buttons on cooldown.

#### Button Column, Button Name, and Effect/Notes

*All numbers are a WIP.*

**Column 1**

- **Gingerly Touch the Orb** — Earn 1 mana, lose 5 Health (button has a cooldown, only one click per second).
- **Make Something / Summon Familiar** — Costs 1 mana to start and increases in cost (by 1 for now) for each familiar owned. The first time the button is pushed it changes names to "Summon Familiar."
- **So hungry / Eat [Bread]** — Button appears after the first familiar is spawned, gain 10 health, only 1 click per 5 seconds. Cooldown only recharges if one familiar exists.
- **Stop Sitting on the Floor** — Adds Chair (button appears after eating food twice. Costs 1 familiar, HP increases/regenerates by +1 every minute, increases orb mana gain by 1. Removes this button, adds chair to area description).
- **Something to eat on** — Adds Rickety Table (button appears after eating food five times and having 3 familiars. Costs 2 familiars, Eat Food HP benefit health restore increased by 2, increases orb mana gain by 2. Removes this button, adds rickety table to area description).
- **Somewhere to rest** — Adds Bed (button appears upon owning 5 familiars. Costs 4 familiars, Max health increased by 20, increases orb mana gain by 3. Removes this button, adds table to area description).
- **A Plinth for the Orb** — Provides an option in the second column for "Orb Channeling." This isn't a button. It has a small up arrow and down arrow next to the name. Increasing the number assigns a free familiar to this job. Increasing mana per second up by 1.

**Column 2**

- **Gain confidence** — Spend 10 mana, changes "gingerly touch the orb" into "carefully touch the orb," Orb mana gain increased by 3, HP loss increased by 5, change to confidence 2.
- **Gain confidence 2** — Spend 20 mana, changes "carefully touch the orb" into "Place your hand on the orb," Orb mana gain increased by 5, HP loss increased by 5, change to confidence 3.
- **Gain confidence 3** — Spend 50 mana, changes "Place your hand on the orb" into "Place both hands on the orb," Orb mana gain increased by 7, HP loss increased by 5, change to confidence 4.
- **Gain confidence 4** — Spend 100 mana, changes to "Hold the orb for a moment," Orb mana gain increased by 10, HP loss increased by 5.
- **A better meal** — Cost starts at 10 mana, costs double (×2) each time it is used. Goes through the food name list, increases HP restoration by +5 each upgrade. Button is only available once the matching table upgrade has already been purchased.
- **A better chair** — Cost starts at 2 familiars, doubling each upgrade (×2), each upgrade HP increases/regenerates by +1 every minute, increases orb mana gain by +1. Adds next chair to area description. This can happen 4 times. Remove button after last chair upgrade.
- **A better table** — Cost starts at 4 familiars, doubling each upgrade (×2). For each level, Eat Food HP restore increased by 2, increases orb mana gain by 2. Removes this button, adds better table to area description.
- **A better bed** — Cost starts at 8 familiars, doubling each upgrade (×2). *(Effect not yet defined.)*

#### Table Name / Food Name progression

Food Name once "Imagine better food" is purchased:

| Table Name | Food Name |
|---|---|
| Rickety Table (purchased with "Something to eat on" upgrade) | Bread |
| A Plain Table | Soup |
| A Sturdy Table | Stew |
| A Fine Table | Roast |
| A Handsome Table | Shepard's Pie |

### Ritual Site

The Ritual Site has the central pedestal, a worksite, and 4 distinct areas with magic circles marked for the different pillars that are each visible far in the distance. All of these seem to be in disrepair.

The ritual site requires a number of resources to restore it to functioning. The magic circles can be restored one at a time or all restored before traveling into them.

**Primary Resources** - Generated just by assigning familiars to this gathering role. Not all are unlocked at start. All require destroying some familiars in order to clear them and then familiars can be assigned to gathering.

- Stone
- Wood
- Water
- Crystals

**Created Resources:** Arcane Dust, Arcane Ink, Charcoal, Chiseled Stone, Sigil Inscribed Stone.

**Purchases:**

- Repair Workbench - Unlocks the creation of other benches
- Familiar Shattering Station - Shatter familiars into Arcane Dust
- Crystal Crushing Station - Crush crystals into crystal dust
- Ink cauldron - spends charcoal, crushed crystals, arcane dust to make arcane ink
- Stone Chiseling Station - Turn raw stone into Chiseled Stone
- Charcoal burner - Turn wood into Charcoal
- Inscribing station - Turns Chiseled Stone, and Arcane Ink into Sigil Inscribed Stone

Sigil Inscribed Stone is the main resource used to repair the magic circles. Each Magic Circle requires more chiseled stone compared to the last.

Once repaired, each magic circle requires a certain amount of familiars to be assigned to it to channel mana, requiring a certain number of familiars and a certain amount of mana per second. This feedback loop forces the player to at least upgrade the house to a certain level and hopefully trap them in the upgrade game.

Once all 4 circles are charged, the player can place the blue orb on the pedestal, beginning a countdown of say 45 seconds. During this time the player can choose to go through the portal.

**MVP Note:** Here we can have the player feed blue mana into the magic circles, charging the far off pillars, opening the portal home. This is the first ending to the game and is all we have to make if we decide to stop here. In our MVP version, there is no countdown — placing the orb ends the game.

Further Areas and Mechanics will be fleshed out in the Stretch Goal Area of this document.

## 7. User Interface

The game is just text and buttons, in the same vein as Universal Paperclips. 2 to 3 columns of text and buttons for things. I would like to have a text box at the bottom for logging and flavor. I would like to eventually have a window to the top right that has some very limited visuals.

(Stretch Goal: Have dark mode.)

## 8. Controls

Just clicking buttons.

## 9. Audio

None.

(Stretch Goal: Maybe some sfx for the buttons that are related to what the button does…maybe.)

## 10. Technical Design

**Engine** - Godot

**Save System** - We need one. Initially it would need to save to browser cookies. We might want to also create one for saving to file since we'll be running it as a standalone for a bit.

**Supported Resolutions** - We'll need to adjust things based on screen resolution. We don't need to design it for mobile, but different monitor sizes would be good.

## 11. Monetization

Ideas:

- We could host it on a website of our own making. We could put a banner ad on it. I don't know if that would even pay the hosting costs though.
- We could put it on itch.io and ask for donations, but web games that aren't downloaded don't even hit the donation splash screen so it likely wouldn't be much.
- If we get popular enough we could put "a more full version" on Steam and/or mobile.

## 12. Accessibility

**Colorblind** - Basically already supported since it is just text.

(Stretch Translations - We should try to do this at least into a couple major languages. Foreign audiences do not get much indie game love.)

## 13. Stretch Ideas

### Ritual Pillar Sites

Rather than go through the ritual site portal with the magical circles charged, the player can instead travel to the pillar sites themselves. These are themed, each with their own mana types and incrementals.

**Possible Themes:**
- Fire / Air / Earth / Water
- Iron / Copper / Silver / Gold (other metals?)
- Wood / Water / Crystal / Stone (I kinda like this idea since it themes with the resources)

**Wood** - A pillar that is a living, talking Elm tree. It is a reference to the Deku Tree and has a spider inside of it that is killing it from the inside. In return for defeating the spider and saving his life, the tree agrees to assist you by channeling energy. This is our first "number go down" area. The incremental here involves channeling mana into the tree's roots to create Elm-Ent-als (they are Ents that are Elms) that help kill the spiderlings. Different Elmentals kill different sized spiders. Once all the spiderlings are dead, eventually a "boss fight" with the spider matriarch inside the tree — imagining a very low pixel view of the spider in a web (think Game Boy graphics). You aim with buttons (stretch or arrow keys) to move a targeting box. The spider starts in the middle of its web, then moves with every shot. On the second shot, if the player would hit the spider, it "dodges" the player shot and the web is broken; a noticeable exclamation point appears above the spider's head. The spider tanks hits from then on. Every round the player takes damage. After a reasonable amount of hits, the player retreats to the laughter of the spider, who calls after the player "foolish magician, I'm invincible in my web!" The spider is actually invincible — it is defeated by destroying 3 (balancing?) of the spider's web connecting threads. Every other round the spider repairs a single web strand.

**Stone** - A pillar made from a trapped stone golem. He laments that he "had such big good strong hands" (a reference to The NeverEnding Story). He might make an offhanded comment about a horse. He makes a replacement pillar for you when you release him.

**Water** - Fortress of solitude, Superman reference? With the lone defender spewing insults at the player, a Monty Python reference.

**Crystal** - A pillar that looks almost like a snowflake, with fractals of crystal branching out (a reference to the Crystalline Entity from Star Trek). This pillar fires an absorption beam at what we are doing, which slows down progress. The crystal has its own incremental that is in full view of the player, purchasing upgrades and so on. The goal is to build a shield that encases the entity. The entity fires a beam that absorbs some of the player's resources, growing stronger — the stronger the entity gets, the more % of resources it absorbs. So it is a sort of dueling incremental against the game. We would need to put in place some "mana bomb" that would let the player restart if the crystal entity gets too powerful.

*I'd love to know your thoughts/ideas here. We could use other references. Once we pick something I'll come up with the mechanics for each of these.*

**Ending:** The player is now able to return home with the orb. It loses much of its power upon returning, but the player is able to use it to provide a good and simple life for his family. They are fed and protected. About the time war ends, the orb loses the last of its power and life returns to normal.

### Town

Mechanics / Ending — not yet fleshed out.

### Other mechanics

- Maze Solving Area — Tower up 100 levels, down 1000 levels, infinite procedural mazes?
- Tribal Wars-style strategic combat.

Endings always end with the orb "losing much of its power," but the player returns more powerful with each ending. With each ending the world they return to slowly improves, then the player eventually becomes stronger and therefore more noticed and important, until the endings start to get darker as the player moves to conquer earth, and eventually the universe.

### Mockup

See `docs/mockups/2a_house_tab.png`. (Original note: "Like this, but I don't expect all the color and good visuals….I feel less capable the more I look at this.")
