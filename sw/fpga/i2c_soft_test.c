
int scl_pin = 10;
int sda_pin = 11;

int current_sda;
int current_scl;

void setup(){
    pinMode(scl_pin, OUTPUT);
    pinMode(sda_pin, OUTPUT);

    release_scl(scl_pin, 1);
    release_scl(sda_pin, 1);
}

void loop(){
    delay(1);
    send_byte('A');
}   

void start(){
    release_scl(scl_pin, 1); // scl still 1
    digitalWrite(sda_pin, 0); // but sda changed to 0 (start)
}

void start(){
    release_scl(scl_pin, 1); // scl still 1
    release_scl(sda_pin, 1); // but sda changed to 1 (stop)
}

void send_byte(char c_sent){
    start();  // start
    delay(1); // wait 1 clk 
    for(int i = 0; i < 7; i++)
        send_bit( (c_sent << i) & 1 ); 

    stop();
}

void send_bit(char bit_sent){ // must be 0 or 1
    set_low_sda(scl_pin, 0);        // set clock 0 for data prop
    delay(1);                        // wait 1 clk 
    set_sda(bit_sent); // set sda as bit
    delay(1);
    release_scl(scl_pin, 1);
}

void release_scl(){

}

void release_sda(){

}

void set_low_scl(){

}

void set_low_sda(){

}

void set_sda(byte set_bit){

}
/*
    ---___--
    ----_---


*/