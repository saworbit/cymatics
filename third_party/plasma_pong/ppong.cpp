            // grapihcs lib

#include <stdio.h>
#include <stdlib.h>
#include <dos.h>
#include <mem.h>
#include <conio.h>
#include <math.h>
#include <string.h>
#include <time.h>


//prototypes:
void init(void);
void blur(void);
void init_rnd(void);
inline int get_rnd(void);
void make_palette(unsigned char *pal_data);
inline void waves(void);
inline void dots(void);
inline void lines(void);

#define NUM_RENDS	3

int curr_renderer;


int score;

unsigned char numbers[10][7][5] = { { 0, 255, 255, 255, 0,
         						  255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 },

								   { 0, 255, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 255, 255, 255, 0 },

								   { 0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             0, 0, 0, 0, 255,
                             0, 0, 255, 255, 0,
                             0, 255, 0, 0, 0,
                             255, 0, 0, 0, 0,
                             255, 255, 255, 255, 255 },

								   { 0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             0, 0, 0, 0, 255,
                             0, 0, 255, 255, 0,
                             0, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 },

								   { 255, 0, 0, 255, 0,
                             255, 0, 0, 255, 0,
                             255, 0, 0, 255, 0,
                             255, 0, 0, 255, 0,
                             255, 255, 255, 255, 255,
                             0, 0, 0, 255, 0,
                             0, 0, 0, 255, 0 },

								   { 255, 255, 255, 255, 255,
                             255, 0, 0, 0, 0,
                             255, 0, 0, 0, 0,
                             255, 255, 255, 255, 0,
                             0, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 },

								   { 0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 0,
                             255, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 },

								   { 255, 255, 255, 255, 255,
                             0, 0, 0, 0, 255,
                             0, 0, 0, 255, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0,
                             0, 0, 255, 0, 0 },

								   { 0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 },

								   { 0, 255, 255, 255, 0,
                             255, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 255,
                             0, 0, 0, 0, 255,
                             255, 0, 0, 0, 255,
                             0, 255, 255, 255, 0 } };

int rnd_tbl[1024];
int locc;
float speed;
bool noisey;

float neb_x[25],neb_y[25];
float neb_dx[25], neb_dy[25];
unsigned char neb_a[25];


double cosTable[255], sinTable[255];

inline int get_rnd(void)
{
   int ret = rnd_tbl[locc++];
   if (locc > 1024) {locc ^= locc;}
   return ret;
}

void init_rnd(void)
{
	locc = 0;
	for (int i = 0; i < 1024; i++)
   {
       rnd_tbl[i] = rand();
   }
}



int mouse_x, mouse_y;
unsigned short **target, /*target_x[320],target_y[200],*/ colors[12*255];

float ball_x,ball_y,ball_x_delta,ball_y_delta,x_temp, y_temp;



#define VIDEO_INT           0x10      // the BIOS video interrupt.
#define WRITE_DOT           0x0C      // BIOS func to plot a pixel.
#define SET_MODE            0x00      // BIOS func to set the video mode.
#define VGA_256_COLOR_MODE  0x13      // use to set 256-color mode.
#define TEXT_MODE           0x03      // use to set 80x25 text mode.

#define SCREEN_WIDTH        320       // width in pixels of mode 0x13
#define SCREEN_HEIGHT       200       // height in pixels of mode 0x13
#define SCREEN_SIZE         (word)(SCREEN_WIDTH*SCREEN_HEIGHT)
#define NUM_COLORS          256       // number of colors in mode 0x13

#define DISPLAY_ENABLE      0x01      // VGA input status bits
#define INPUT_STATUS    			0x03da
#define VRETRACE            0x08

#define PALETTE_MASK					0x03c6
#define PALETTE_REGISTER_READ 	0x03c7
#define PALETTE_REGISTER_WRITE 	0x03c8
#define PALETTE_DATA 				0x03c9

typedef unsigned char  byte;
typedef unsigned short word;


void draw_text(byte * buffer,int x, int y);

#define NUM_PALETTES          	4
unsigned char pal_table[NUM_PALETTES][66] = {{  5,
                                                0,  31,
                                       			0,   0,   0,
                                       			0,   0,  63,

                                      			  32,  63,
                                       			0,   0,  63,
                                       			0,   0,   0,

                                      			  64,  95,
                                       			0,   0,   0,
                                      			  63,   0,   0,

                                      			  96, 127,
                                      			  63,   0,   0,
                                      		 		0,   0,   0,

                                     			 128, 255,
                                       			0,   0,   0,
                                   				  63,  63,   0,

                                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1  },

                                             {  5,
                                                0,  31,
                                       			0,   0,   0,
                                       			21,   39,  23,

                                      			  32,  63,
                                       			21,   39,  23,
                                       			63,   19,   0,

                                      			  64,  95,
                                       			63,   19,   0,
                                      			  32,   33,   27,

                                      			  96, 127,
                                      			  32,   33,   27,
                                      		 		26,   5,   18,

                                     			 128, 255,
                                       			26,   5,   18,
                                   				  63,  63,   0,

                                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1  },

                                             {  5,
                                                0,  31,
                                       			0,   0,   0,
                                       			21,   33,  40,

                                      			  32,  63,
                                       			21,   33,  40,
                                       			12,   12,   20,

                                      			  64,  110,
                                       			12,   12,   20,
                                      			  43,   33,   38,

                                      			  111, 127,
                                      			  43,   33,   38,
                                      		 		63,   17,   3,

                                     			 128, 255,
                                       			63,   17,   3,
                                   				  54,  46,   30,

                                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,1  },

                                             {  5,
                                                0,  31,
                                       			0,   0,   0,
                                       			57,   57,  63,

                                      			  32,  63,
                                       			57,   57,  63,
                                       			0,   0,   0,

                                      			  64,  110,
                                       			0,   0,   0,
                                      			  63,   63,   63,

                                      			  111, 127,
                                      			  63,   63,   63,
                                      		 		0,   0,   0,

                                     			 128, 255,
                                       			0,   0,   0,
                                   				  63,  63,   63,

                                               0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0  }

                                               };



byte *vga=(byte *)0xA0000000L;        //location of video memory
byte *d_buffer,*x_buffer;

void set_mode(byte mode);
void set_pixel(byte *buffer, int x,int y,byte color);
void show_buffer(byte *buffer);
void s_pal_entry( unsigned char index,
						unsigned char red,
                  unsigned char green,
                  unsigned char blue );
void line(byte * buffer, int x1, int y1, int x2, int y2, unsigned char color);

void set_mode(byte mode)
{
  union REGS regs;

  regs.h.ah = SET_MODE;
  regs.h.al = mode;
  int86(VIDEO_INT, &regs, &regs);

 //allocate mem for the d_buffer
 if ((d_buffer = (byte *) malloc(SCREEN_SIZE)) == NULL)
  {
    printf("Not enough memory for double buffer.\n");
    exit(1);
  }

  if ((x_buffer = (byte *) malloc(SCREEN_SIZE)) == NULL)
  {
    printf("Not enough memory for double buffer.\n");
    exit(1);
  }
}

inline void set_pixel(byte *buffer, int x,int y,byte color)
{
  buffer[y*SCREEN_WIDTH+x]=color;
}

inline void show_buffer(byte *buffer)
{
	while  ((inp(INPUT_STATUS) & VRETRACE));
   while (!(inp(INPUT_STATUS) & VRETRACE));

	memcpy(x_buffer,buffer,SCREEN_SIZE);
  	memcpy(vga,buffer,SCREEN_SIZE);
}

inline void s_pal_entry( unsigned char index,
		  				unsigned char red,
                  unsigned char green,
                  unsigned char blue )
{
	outp(PALETTE_MASK,0xff);
	outp(PALETTE_REGISTER_WRITE, index); //tell it what index to use (0-255)
	outp(PALETTE_DATA, red); //enter the red
	outp(PALETTE_DATA, green); //green
	outp(PALETTE_DATA, blue); //blue
}


void line(byte * buffer, int x1, int y1, int x2, int y2, unsigned char color)
     {
             int dx, dy, xinc, yinc, two_dx, two_dy, x = x1, y = y1, i, error;

             if (x1 == x2 && y1 == y2) {
                     set_pixel(buffer, x1,y1, color);
                     return;
             }

             dx = (x2 - x1);
             if (dx < 0) { dx = -dx; xinc = -1; }
             else xinc = 1;

             dy = (y2 - y1);
             if (dy < 0) { dy = -dy; yinc = -1; }
             else yinc = 1;

             two_dx = dx + dx; two_dy = dy + dy;

             if (dx > dy) {
                     error = 0;
                     for (i = 0; i < dx; i++) {
                             set_pixel(buffer, x, y, color);
                             x += xinc;
                             error += two_dy;
                             if (error > dx) {
                                     error -= two_dx;
                                     y += yinc;
                             }
                     }
             } else {
                     error = 0;
                     for (i = 0; i < dy; i++) {
                             set_pixel(buffer, x, y, color);
                             y += yinc;
                             error += two_dx;
                             if (error > dy) {
                                     error -= two_dy;
                                     x += xinc;
                             }
                     }
             }
}

///--------------main stuff

int main(void)
{
	init();

   union REGS r;
   r.x.bx=0;
   while(r.x.bx !=3)
   {
   	r.x.ax = 3;
  		int86(0x33, &r, &r);

  		mouse_x = r.x.cx * 0.420062695924 + 26;
  		mouse_y = r.x.dx * 0.74 + 26;

		switch(curr_renderer)
      {
      	case 0: waves(); break;
         case 1: dots(); break;
         case 2: lines(); break;
      }

      x_temp = ball_x;
      y_temp = ball_y;

      ball_x += ball_x_delta;
      ball_y += ball_y_delta;

      if(ball_x > 305 || ball_x < 15 || ball_y > 185 || ball_y <15)
		{
         if(ball_x > 319 || ball_x < 0 || ball_y > 199 || ball_y <0){
         	   ball_x=160; ball_y=100;
  	 				ball_x_delta=(get_rnd()%2) ? 2.3 : -2.3; ball_y_delta=(get_rnd()%2) ? 2.3 : -2.3;
               speed=2.3;
					for(; score>0; score--)
               {
//               	draw_text(x_buffer,150,91);
               	blur();
                  show_buffer(d_buffer);
//               	draw_text(x_buffer,150,91);
               	blur();
                  show_buffer(d_buffer);
               }
               init_rnd();
            	make_palette(pal_table[get_rnd()%NUM_PALETTES]);
               curr_renderer=get_rnd()%NUM_RENDS;
               score = 0;
         }
	      if(ball_y > (mouse_y - 18) && ball_y < (mouse_y+18) && ball_x <13)
	      {
         	speed+=.05;
	      	ball_x_delta = speed;
            ball_x = x_temp;
	         ball_y_delta = (ball_y-mouse_y)/4;
            make_palette(pal_table[get_rnd()%NUM_PALETTES]);
            curr_renderer=get_rnd()%NUM_RENDS;
            score++;
	      }
	      else if(ball_y < (199-(mouse_y - 18)) && ball_y > (199-(mouse_y+18)) && ball_x >307)
	      {
         	speed+=.05;
	      	ball_x_delta = -1*speed;
            ball_x = x_temp;
	         ball_y_delta = (ball_y-(199-mouse_y))/4;
            make_palette(pal_table[get_rnd()%NUM_PALETTES]);
            curr_renderer=get_rnd()%NUM_RENDS;
            score++;
	      }
         else if(ball_x < (319-(mouse_x - 18)) && ball_x > (319-(mouse_x+18)) && ball_y <13)
	      {
         	speed+=.05;
	      	ball_y_delta = speed;
            ball_y = y_temp;
	         ball_x_delta = (ball_x-(319-mouse_x))/4;
            make_palette(pal_table[get_rnd()%NUM_PALETTES]);
            score++;
            curr_renderer=get_rnd()%NUM_RENDS;
	      }
	      else if(ball_x > (mouse_x - 18) && ball_x < (mouse_x+18) && ball_y >188)
	      {
         	speed+=.05;
	      	ball_y_delta = -1*speed;
            ball_y = y_temp;
	         ball_x_delta = (ball_x-mouse_x)/4;
            make_palette(pal_table[get_rnd()%NUM_PALETTES]);
            score++;
            curr_renderer=get_rnd()%NUM_RENDS+1;
      	}
      }


      //draw paddles

   	blur();

//      draw_text(d_buffer,10,10);

      line(d_buffer,319-(mouse_x-16),10,319-(mouse_x+16),10,255);
      line(d_buffer,mouse_x-16,190,mouse_x+16,190,255);
      line(d_buffer,10,mouse_y-16,10,mouse_y+16,255);
      line(d_buffer,310,199-(mouse_y-16),310,199-(mouse_y+16),255);

      for(int i=0; i <5; i++)
      {
      	line(d_buffer,(int)ball_x+get_rnd()%6-3,(int)ball_y+get_rnd()%6-3,(int)ball_x+get_rnd()%6-3,(int)ball_y+get_rnd()%6-3,230);
      }

      float tempX;
		for(int i=0; i <25; i++)
      {

       	tempX = neb_x[i];

         neb_x[i] = neb_x[i] * cosTable[neb_a[i]] -   neb_y[i] * sinTable[neb_a[i]];
         neb_y[i] = neb_y[i] * cosTable[neb_a[i]] + tempX * sinTable[neb_a[i]];

         neb_dx[i]=neb_x[i]+ball_x;
         neb_dy[i]=neb_y[i]+ball_y;

			set_pixel(d_buffer,neb_dx[i],neb_dy[i],255);
      }


      show_buffer(d_buffer);
   }

   for (int i = 0; i < 320; i++)
   {
   	delete target[i];
   }
   delete[] target;

	return 0;
}

void make_palette(unsigned char *pal_data)
{
	char num_elems = pal_data[0],
   	  elem_start,
        elem_end,
        difference,
        red_start,
        red_end,
        green_start,
        green_end,
        blue_start,
        blue_end;

   float red_inc,
         green_inc,
         blue_inc,
         working_red,
         working_green,
         working_blue;

   for (int i = 1; i <= num_elems*8; i+=8)
   {
      elem_start = pal_data[i];
      elem_end = pal_data[i+1];
      difference = abs(elem_end - elem_start);

   	red_start = pal_data[i+2];
   	green_start = pal_data[i+3];
   	blue_start = pal_data[i+4];
   	red_end = pal_data[i+5];
   	green_end = pal_data[i+6];
   	blue_end = pal_data[i+7];

      working_red = red_start;
      if (working_red < 0) working_red = 0;
      else if (working_red > 63) working_red = 63;
      red_inc = (float)(red_end - red_start) / (float)difference;

      working_green = green_start;
      if (working_green < 0) working_green = 0;
      else if (working_green > 63) working_green = 63;
      green_inc = (float)(green_end - green_start) / (float)difference;

      working_blue = blue_start;
      if (working_blue < 0) working_blue = 0;
      else if (working_blue > 63) working_blue = 63;
      blue_inc = (float)(blue_end - blue_start) / (float)difference;

      for (int j = elem_start; j <= elem_end; j++)
      {
      	s_pal_entry(j, int(working_red), int(working_green), int(working_blue));

         working_red += red_inc;
	      if (working_red < 0) working_red = 0;
	      else if (working_red > 63) working_red = 63;

         working_green += green_inc;
	      if (working_green < 0) working_green = 0;
	      else if (working_green > 63) working_green = 63;

         working_blue += blue_inc;
	      if (working_blue < 0) working_blue = 0;
	      else if (working_blue > 63) working_blue = 63;
      }
   }

   if (pal_data[65]) noisey = true;
   else noisey = false;
}

void blur(void)
{
	int new_color;

   /*   int rand_x=0, rand_y=0;
   rand_x=rand()%4-2; rand_y=rand()%4-2; */
	for(int y=0; y < 200; y++)
   {
   	for(int x=0; x < 320; x++)
      {

      	new_color=0;

      	new_color += (x_buffer[target[x][y]])<<3;

         new_color += x_buffer[target[x][y]+1];
         new_color += x_buffer[target[x][y]+SCREEN_WIDTH];

         new_color += x_buffer[target[x][y]-1];
         new_color += x_buffer[target[x][y]-SCREEN_WIDTH];

         new_color =colors[new_color];
         if(noisey) new_color+=get_rnd()%2-1;
         if(new_color >255){new_color=255;}
         if(new_color <0){new_color=0;}
         set_pixel(d_buffer,x,y,new_color);
      }
   }
}

void init(void)
{
	score = 0;
	srand(15);
   init_rnd();
	set_mode(VGA_256_COLOR_MODE);
   memset(d_buffer,0,SCREEN_SIZE);
   memset(x_buffer,0,SCREEN_SIZE);

   make_palette(pal_table[get_rnd()%NUM_PALETTES]);
   curr_renderer=get_rnd()%NUM_RENDS+1;

   int x,y;
   double newx, newy;

   target = new unsigned short * [320];
   if (!target)
   {
   	fprintf(stderr, "Unable to allocate target array 1");
      exit(1);
   }
   for (int i = 0; i < 320; i++)
   {
   	target[i] = new unsigned short[200];
	   if (!target)
	   {
	   	fprintf(stderr, "Unable to allocate target array 2");
	      exit(2);
	   }
   }

   for (y = 0; y < 200; y++)
   {
   	for (x = 0; x < 320; x++)
      {
         newx = ((x-160)/1.03) + 160;
         newy = ((y-100)/1.03) + 100;
         newx = newx > 319 ? 319 : (unsigned short)(newx);
         newx = newx < 0 ? 0 : (unsigned short)(newx);
         newy = newy > 199 ? 199 : (unsigned short)(newy);
         newy = newy < 0 ? 0 : (unsigned short)(newy);
         target[x][y] = (newy * 320) + newx;
      }
   }

 /*  for(int i=0; i <320; i++)
   {
     	target_x[i] = ((i - 160)/1.03)+160;
   }

   for(int i=0; i <200; i++)
   {
   	target_y[i] = ((i - 100)/1.03)+100;
   }
   */



   for(int i=0; i <(12*255); i++)
	{
   	colors[i]=i/12.1;
   }

   ball_x=160; ball_y=100;
   speed=2.3;
   ball_x_delta=(get_rnd()%2) ? 2.3 : -2.3; ball_y_delta=(get_rnd()%2) ? 2.3 : -2.3;

   for(int i=0; i < 25; i++)
   {
   	//neb_x[i] = get_rnd()%40-20;
      //neb_y[i] = get_rnd()%40-20;
      neb_x[i] = get_rnd()%3-5;
      neb_y[i] = get_rnd()%3-5;
      neb_a[i] = get_rnd()%30-15;
   }

	for( int i = 0; i!=255; i++ ){
		cosTable[i] = cos( ((2*3.1415)/256)*i );
      sinTable[i] = sin( ((2*3.1415)/256)*i );
   }
   curr_renderer = 0; 

}

inline void waves(void)
{
		int vertices[11];
		for(int i=0; i <=10; i++)
      {
      	vertices[i]=get_rnd()%60+60;
      }
     	for(int i=0; i<10; i++)
      {
      	line(x_buffer,i*32,vertices[i],i*32+32,vertices[i+1],128);
      }
      int drop_x=get_rnd()%319,drop_y=get_rnd()%119;
      set_pixel(x_buffer,drop_x,drop_y,255);
      set_pixel(x_buffer,drop_x+1,drop_y,255);
      set_pixel(x_buffer,drop_x-1,drop_y,255);
      set_pixel(x_buffer,drop_x,drop_y+1,255);
      set_pixel(x_buffer,drop_x,drop_y-1,255);
}

void draw_text(byte *buffer, int x, int y)
{
	char text[6];

   sprintf(text, "%d", target[313][20]);

   for ( int i = 0; i < strlen(text); i++)
   {
     	for (int y_loop = 0; y_loop < 7; y_loop++)
      {
      	for (int x_loop = 0; x_loop < 5; x_loop++)
         {
         	set_pixel(buffer, x_loop + x + (i*7), y_loop + y, numbers[text[i]-48][y_loop][x_loop]);
         }
      }
   }
}

inline void dots(void)
{      
	for(int i=0; i <8; i++)
   {
		int drop_x=get_rnd()%319,drop_y=get_rnd()%199;
      set_pixel(x_buffer,drop_x,drop_y,255);
      set_pixel(x_buffer,drop_x+1,drop_y,255);
      set_pixel(x_buffer,drop_x-1,drop_y,255);
      set_pixel(x_buffer,drop_x,drop_y+1,255);
      set_pixel(x_buffer,drop_x,drop_y-1,255);
   }
}

inline void lines(void)
{      

	line(x_buffer,get_rnd()%319,get_rnd()%199,get_rnd()%319,get_rnd()%199,get_rnd()%255);

}
