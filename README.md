# Factorio Plots Server

This is a proof of concept for a factorio plots server script / mod

The idea is to allow players to join and "rent" plots, and have them only be
allowed to interact with plots that they have rented. This should remove the
possibility of griefing while still allowing players to build their own factory
on a public server without risking it being griefed

Currently the system of plot renting and anti-griefing works, for the most part.
However I don't consider this complete

At the moment no more work is being done on this until Factorio updates their
Lua API, as currently it is impossible to implement some required features

### Running the server
The control.lua script can either be run as a scenario or included in a mod.
If included in a mod rather than a scenario script, all clients must have the
mod installed to join

Some settings that I think work well with a plot size of 5 chunks, bear in mind
that players need to have all the resources they need in their initial few
plots:
- Terrain Segmentation: High
- Water: Small
- Iron: High, Big, Very Good
- Copper: High, Big, Very Good
- Stone: Very High, Big, Very Good
- Coal: Very High, very Big, Very Good
- Crude Oil: High, Big, Very Good
- Enemy Bases: Normal, None, Regular
- Starting Area: None
- Peaceful Mode: ON
- 16000x16000 tiles (100x100 plots = 10000 plots total)

If the server is public, you should start the server with --disallow-commands
to prevent cheating

### To-Do list
Much of the to-do list depends on features being added to the Lua API. At the
moment it is very difficult to prevent any actions made by the player

- Prevent players from manually mining neutral resources (e.g trees, ore) in
  other territories
  - It might be possible to prevent this by creatively using the
  on_preplayer_mined_item and on_player_mined_item events, but I'm hoping the
  API will be improved at some point to make this easier
- Some sort of coin gain
  - At the moment the player starts with coins, but has no way to gain them
  - A Market building would work - allowing the player to sell produced items
  for coins
  - A daily reward for logging in would also be sensible
- Prevent players from picking up items in other plots
  - While there is an event for this ("on_picked_up_item"), it does not mention
  where the item is picked up from so it is not possible to revert or prevent
  the action
  - We could teleport the player back to the road if they enter another player's
  plot, but that seems mean
- Allow players to obtain alien artifacts
  - Alien bases can't be allowed to spawn, since new players can join at any
  time after the server is started
  - Probably the best way would be to allow purchase of artifacts through a
  market, using coins
  - Perhaps a "quest" system might also work, giving artifacts as rewards
- Stop players from killing each other with cars
  - Making players immortal would work fine
- Allow players to give others access to their plots
  - Merging the player's forces would work fine here, though the players would
  also share research and everything else (essentially being on the same team)
- Authenticate players when joining
  - [This is probably coming in 0.13 along with the multiplayer matching server.](https://forums.factorio.com/viewtopic.php?f=3&t=678) (If not, then it
  will likely come soon after)
- Remove pollution as it spawns
  - Since there are no enemies, pollution doesn't do anything except load chunks
  unnecessarily, which might cause lag

### License
This project is licensed under the terms of the MIT license
