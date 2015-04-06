#include <SFE_BMP180.h>
#include <Wire.h>
#include <SPI.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <Button.h>
#include <EEPROM.h>
#include "EEPROMAnything.h"

// If using software SPI (the default case):
#define OLED_MOSI   9
#define OLED_CLK   10
#define OLED_DC    11
#define OLED_CS    12
#define OLED_RESET 13

#define BUTTON1_PIN     4

#define HPA 0
#define METER 1
#define DEG 2

Adafruit_SSD1306 display(OLED_MOSI, OLED_CLK, OLED_DC, OLED_RESET, OLED_CS);

/* Uncomment this block to use hardware SPI
 #define OLED_DC     6
 #define OLED_CS     7
 #define OLED_RESET  8
 Adafruit_SSD1306 display(OLED_DC, OLED_RESET, OLED_CS);
 */

extern uint8_t Font24x40[];
extern uint8_t Symbol[];
extern uint8_t Spash[];

SFE_BMP180 pressure;
Button button1 = Button(BUTTON1_PIN,BUTTON_PULLDOWN);
boolean longPush = false;
int value, etat = 0;
double QNH, saveQNH;
double temperature, pression, altitude = 0;
double baseAltitude, saveBaseAltitude = 0;
double altiMin = 9999.0;
double altiMax = 0.0;
double lastValue = 0.0;
int eepromAddr = 10;

#define MAX_SAMPLES 20
double samplesBuffer[MAX_SAMPLES];
int indexBfr = 0;
double averagePressure = 0;
boolean bufferReady = false;
int screen = 0; // numero d'ecran
#define NB_SCREENS 5
String debugMsg;

/* ------------------------------------ setup ------------------------------------------ */
void setup()   {                
  button1.releaseHandler(handleButtonReleaseEvents);
  button1.holdHandler(handleButtonHoldEvents,2000);

  display.begin(SSD1306_SWITCHCAPVCC);

  // init QNH
  EEPROM_readAnything(eepromAddr, QNH);
  if (isnan(QNH)) {
    QNH = 1013.25;
    EEPROM_writeAnything(eepromAddr, QNH);  // QNH standard 
  }
  saveQNH = QNH;

  display.clearDisplay(); 
  display.drawBitmap(0, 0,  Spash, 128, 64, 1);
  display.display();
  delay(1000);
  display.clearDisplay(); 
  display.setTextSize(1);
  display.setTextColor(WHITE);
  display.setCursor(0,0);
  if (!pressure.begin()) {
    display.println("Init fail !");
    display.println("Turn OFF");
    display.display();
    while(1); // Pause forever.
  }

  button1.isPressed();
  screen = 1;
}

/* ------------------------------------ loop ------------------------------------------ */
void loop() {
  char status;

  button1.isPressed();

  // get pressure and temperature and calculate altitude 
  status = pressure.startTemperature();
  if (status != 0) {
    delay(status);
    status = pressure.getTemperature(temperature);
    if (status != 0) {
      status = pressure.startPressure(0);
      if (status != 0) {
        delay(status);
        status = pressure.getPressure(pression, temperature);
        if (status != 0) {
          savePressureSample(pression);
          averagePressure = getPressureAverage();
          if (bufferReady) {
            altitude = pressure.altitude(averagePressure*100, QNH*100);
            setAltiMinMax();
          }

        }
      } 
    } 
  }

  if (etat == 0) {
    // init baseAltitude
    if (baseAltitude == 0) { 
      baseAltitude = round(altitude);
      saveBaseAltitude = baseAltitude;
    }
    // calculate QNH
    if (baseAltitude != saveBaseAltitude) {
      QNH = pressure.sealevel(pression, baseAltitude);
      saveBaseAltitude = baseAltitude;
    }
     // Save QNH in EEPROM
    if (QNH != saveQNH) {
      saveQNH = QNH;
      EEPROM_writeAnything(eepromAddr, QNH);
    }

    switch (screen) {
    case 1: // Altitude
      if (lastValue != altitude) {
        showScreen("ALTITUDE", altitude, METER);
        lastValue = altitude;
      }  
      break;

    case 2: // Altitude Max
      if (lastValue != altiMax) {
        showScreen("ALTITUDE MAX", altiMax, METER);
        lastValue = altiMax;
      }  
      break;

    case 3:  // Altitude Min
      if (lastValue != altiMin) {
        showScreen("ALTITUDE MIN", altiMin, METER);
        lastValue = altiMin;
      }  
      break;

    case 4:  // Pression
      if (lastValue != pression) {
        showScreen("PRESSION", pression, HPA);
        lastValue = pression;
      }  
      break;

    case 5:  // Temperature
      if (lastValue != temperature) {
        showScreen("TEMPERATURE", temperature, DEG);
        lastValue = temperature;
      }  
      break;
    }
  }
  else { // Settings
    // Settings
    display.clearDisplay(); 
    display.setTextSize(1);
    display.setCursor(0,0);
    display.println("CALIBRATION");
    display.setCursor(0,15);
    display.print("QNH : ");
    display.print(QNH,2);
    display.println(" hPa");    
    //display.print("Debug : ");
    //display.println(debugMsg);
    //display.print("Etat : ");
    //display.println(etat);
    if (etat == 1) drawSymbol(100, 40, 3); //UP
    if (etat == 2) drawSymbol(100, 40, 4); // DOWN
    if (value != 0) {
      baseAltitude += value; 
      value = 0; 
      // recalcule le QNH
      QNH = pressure.sealevel(pression, baseAltitude);
    }
    display.setCursor(0,45);
    display.print("Alti : ");
    display.println(baseAltitude, 0);
    display.display();            
  }

  delay(50);
}
/* -------------------- functions --------------------  */

// Display screen data
void showScreen(String label, double value, int unit) {
  display.clearDisplay(); 
  display.setCursor(0,0);
  display.println(label);
  drawFloatValue(0, 20, value, unit);
  display.display();  
}

// Saves sample pressure
void savePressureSample(float pressure) {
  if (indexBfr == MAX_SAMPLES)  {
    indexBfr = 0;
    bufferReady = true;  
  }
  samplesBuffer[indexBfr++] = pressure; 
}

// Returns the average pressure samples
float getPressureAverage() {
  double sum = 0;
  for (int i =0; i<MAX_SAMPLES; i++) {
    sum += samplesBuffer[i];
  }
  return sum/MAX_SAMPLES;
}

// Save altitude Min & Max
void setAltiMinMax() {
  if (altitude > altiMax) altiMax = altitude;
  if (altitude < altiMin) altiMin = altitude;
}
void resetAltiMinMax() {
  altiMax = altiMin = altitude;
}
// Management release the button
void handleButtonReleaseEvents(Button &btn) {
  //debugMsg = "Release";
  if (!longPush) {
    if (etat != 0 ) { // Settings
      if (etat == 1) value = 1;
      if (etat == 2) value = -1;
    } 
    else { // Change screen
      screen++;
      if (screen > NB_SCREENS) screen = 1;
      lastValue = 0;
    }
  }
  longPush = false;
}

// Management support extended on the button
void handleButtonHoldEvents(Button &btn) {
  //debugMsg = "Hold";
  longPush = true;
  screen = 1;
  value = 0;
  if (screen == 1 && ++etat > 2) {
    etat = 0;
    delay(500);
  }
  else if (screen == 2 || screen == 3) {
    resetAltiMinMax();
  }
}

// Displays a character x, y
void drawCar(int sx, int sy, int num, uint8_t *font, int fw, int fh, int color) {
  byte row;
  for(int y=0; y<fh; y++) {
    for(int x=0; x<(fw/8); x++) {
      row = pgm_read_byte_near(font+x+y*(fw/8)+(fw/8)*fh*num);
      for(int i=0;i<8;i++) {
        if (bitRead(row, 7-i) == 1) display.drawPixel(sx+(x*8)+i, sy+y, color);
      }
    }
  }
}

// Displays a big character x, y
void drawBigCar(int sx, int sy, int num) {
  drawCar(sx, sy, num, Font24x40, 24, 40, WHITE) ;
}

void drawDot(int sx, int sy, int h) {
  display.fillRect(sx, sy-h, h, h, WHITE);
}

// Affiche un symbole en x, y
void drawSymbol(int sx, int sy, int num) {
  drawCar(sx, sy, num, Symbol, 16, 16, WHITE) ;
}

// Displays a decimal number
void drawFloatValue(int sx, int sy, double val, int unit) {
  char charBuf[15];
  if (val < 10000) {
    dtostrf(val, 3, 1, charBuf); 
    int nbCar = strlen(charBuf);
    if (nbCar > 5) { // pas de decimal
      for (int n=0; n<4; n++) drawBigCar(sx+n*26, sy, charBuf[n]- '0');
      drawSymbol(108,sy, unit);
    }
    else {
      drawBigCar(sx+86, sy, charBuf[nbCar-1]- '0');
      drawDot(78, sy+39, 6);
      nbCar--;
      if (--nbCar > 0) drawBigCar(sx+52, sy, charBuf[nbCar-1]- '0');
      if (--nbCar > 0) drawBigCar(sx+26, sy, charBuf[nbCar-1]- '0');
      if (--nbCar > 0) drawBigCar(sx, sy, charBuf[nbCar-1]- '0');
      drawSymbol(112,sy, unit);
    }
  }
}
