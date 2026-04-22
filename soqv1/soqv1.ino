#include <PID_v2.h>
#include <Servo.h>
#include <Wire.h>
#include <Adafruit_BNO055.h>
#include <utility/imumaths.h>

Servo panServo;
Adafruit_BNO055 bno = Adafruit_BNO055(55, 0x28, &Wire);

double error = 0;
double correction = 0;
double setpoint = 0;

double Kp = 0.06;
double Ki = 0.00;
double Kd = 0.005;

PID_v2 panPID(Kp, Ki, Kd, PID::Direct);

double servoPos = 90;
const unsigned long PID_UPDATE_MS = 20;
const unsigned long IMU_REPORT_MS = 50;
unsigned long lastPidUpdateMs = 0;
unsigned long lastImuReportMs = 0;
bool imuReady = false;
char serialBuffer[32];
uint8_t serialIndex = 0;

void readIncomingError() {
    while (Serial.available() > 0) {
        char c = (char)Serial.read();

        if (c == '\r') {
            continue;
        }

        if (c == '\n') {
            serialBuffer[serialIndex] = '\0';
            if (serialIndex > 0) {
                error = atof(serialBuffer) * -1;
                error = constrain(error, -90, 90);
            }
            serialIndex = 0;
            continue;
        }

        if (serialIndex < sizeof(serialBuffer) - 1) {
            serialBuffer[serialIndex++] = c;
        } else {
            serialIndex = 0;
        }
    }
}

void reportImuHeading(unsigned long now) {
    if (now - lastImuReportMs < IMU_REPORT_MS) {
        return;
    }

    if (Serial.availableForWrite() < 24) {
        return;
    }

    lastImuReportMs = now;

    if (!imuReady) {
        Serial.println("IMU:0");
        return;
    }

    imu::Vector<3> euler = bno.getVector(Adafruit_BNO055::VECTOR_EULER);
    uint8_t sysCal = 0;
    uint8_t gyroCal = 0;
    uint8_t accelCal = 0;
    uint8_t magCal = 0;
    bno.getCalibration(&sysCal, &gyroCal, &accelCal, &magCal);

    Serial.print("H:");
    Serial.print(euler.x(), 1);
    Serial.print(",IMU:1,CAL:");
    Serial.println(sysCal);
}

void setup() {
    Serial.begin(115200);
    Serial.setTimeout(1);
    panServo.attach(9);
    panServo.write(90);

    panPID.SetOutputLimits(-20, 20);
    panPID.Start(error, 0, setpoint);

    imuReady = bno.begin();
    if (imuReady) {
        delay(1000);
        bno.setExtCrystalUse(true);
    }
}

void loop() {
    unsigned long now = millis();

    readIncomingError();

    if (now - lastPidUpdateMs >= PID_UPDATE_MS) {
        lastPidUpdateMs = now;

        correction = panPID.Run(error);
        servoPos += correction;
        servoPos = constrain(servoPos, 0, 180);
        panServo.write((int)servoPos);
    }

    reportImuHeading(now);
}
