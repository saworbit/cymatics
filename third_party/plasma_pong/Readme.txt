Plasma Pong v1.0
(c) 2006 Steve Taylor

Email: staylor5@gmu.edu
Website: www.PlasmaPong.com

Special Thanks: Jos Stam (Real-time Fluid Dynamics for Games)
		Link: http://www.dgp.toronto.edu/people/stam/reality/Research/pdf/GDC03.pdf

Music:	ES Posthumus - Pompeii
	Harry Gregson-Williams - Training Montage

OVERVIEW:
Plasma Pong is a variant of the popular PONG game, with a high tech twist – it uses computational fluid dynamics 
to drive the environment.  As the game starts you will have to duke it out against the opposing paddle, using the
fluid as your weapon.  To do this you can shoot plasma out of the paddle to push the fluid around, which in turn
pushes the ball around.  Another weapon at your disposal is the ability to suction fluid back into your paddle.
By doing this, possession of the ball can be controlled by the player.  Once the ball is fully sucked into the paddle
you can blast the ball across to the opposing player’s side.  After scoring against the opponent, you will “Level Up”
and the game mechanics will become harder.  The ball will be more reactive to the fluid, making it much more unpredictable.
Lose the ball and you will lose a life. Lose 10 lives and its game over!  Good Luck.


PONG KEYBINDS:
Key:			| Description:
-----------------------------------------------------
Left Mouse Button	|  Shoot plasma jet
Right Mouse Button	|  Create plasma vaccuum  (Release to blast a shockwave)
Spacebar		|  Pause game
'M'			|  Toggle music on/off
'P'			|  Toggle particles on/off
'L'			|  Level up (cheat)
'T'			|  Ball Tracer (cheat)
F1			|  Switch to the interactive fluid solver
F2			|  Toggle Fullscreen Mode

FLUID SOLVER:
The fluid solver is the base engine for the pong game.  I've also included it with the program. Here are the keybinds:

Key:			| Description:
-----------------------------------------------------
Right Mouse Button  	|  Inject densities (ink)
Left Mouse Button   	|  Drag the mouse to add velocities
Middle Mouse Button 	|  Create jets (LMB emits particles, RMB emits densities)
'1'                 	|  Cycle 3D density depth
'2'                 	|  Toggle dye shader
'3'                 	|  Toggle velocity shader
'4'                 	|  Toggle pressure shader
'5'                 	|  Toggle divergence shader
'6'                 	|  Toggle curl shader
'7'                 	|  Toggle velocity grid
'8'                 	|  Toggle velocity lines
'9'                	|  Toggle vorticity lines
'w'                 	|  Toggle wall mode (LMB creates walls, RMB clears walls)
's'                 	|  Toggle sink mode (LMB creates sinks, RMB creates waves)
'g'                 	|  Toggle gravity
'b'                 	|  Toggle buoyancy
'v'                 	|  Toggle vorticity confinement
'r'                 	|  Randomize 3d density colors
'c'                 	|  Clear the simulation
Spacebar            	|  Pause the simulation
'F1'                	|  Switch back to Plasma Pong
'F2'                	|  Toggle Fullscreen mode
'q'                 	|  Quit

BACKGROUND:
Over winter break here at George Mason University, I had no job and too much time on my hands.  So I did what any self-
respecting computer scientist would have done - I made a game.  Something that has always facinated me was the simulation
of fluids, but up until then I had no interest in researching it.  I found Jos Stam's paper titled, "fluid dynamics for games",
which was a breakthrough in terms of developing a simple stable fluid solver.  Unfortunately nobody had really made a good
game using this method as it is very expensive to process.  My program is simply a proof of concept that fluid dynamics are not
just gimmicky eye candy, but it can affect gameplay in a positive way.  My next game, whenever I write it, will improve on this concept.

OPTIMIZATION:
Your computer must be badass, otherwise things will slow down.  There is an FPS counter at the top right-hand corner of the
screen.  If you're FPS dips below 30, open up params.txt and follow the optimization steps at the top.  Note that doing this
will sacrifice quality for performance.

KNOWN BUGS:
There is a small memory leak... I'm working on it.
Various annoying bugs relating to sucking of the ball.