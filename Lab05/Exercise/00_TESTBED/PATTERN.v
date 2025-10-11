`define CYCLE_TIME  20.0

module PATTERN(
    // output signals
    clk,
    rst_n,
    in_valid_data,
    in_valid_param,
    
    data,
	index,
	mode,
    QP,
	
    // input signals
    out_valid,
    out_value
);

//=====================================================================
// I/O declaration
//=====================================================================
// Output
output reg          clk;
output reg          rst_n;
output reg          in_valid_data;
output reg          in_valid_param;

output reg    [7:0] data;
output reg    [3:0] index;
output reg          mode;
output reg    [4:0] QP;

// Input
input               out_valid;
input signed [31:0] out_value;

//=====================================================================
//   PARAMETER & INTEGER DECLARATION
//=====================================================================
//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
// Can be modified by user
integer   TOTAL_PATNUM = 10;
integer   SIMPLE_PATNUM = 100;
integer   SEED = 5487;
parameter DEBUG = 1;
parameter INPUT_CSV = "input.csv";
parameter OUTPUT_CSV = "output.csv";
//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
real      CYCLE = `CYCLE_TIME;
parameter MAX_EXECUTION_CYCLE = 10000;

// PATTERN control
integer pat;
integer param_set;
integer execution_lat;
integer total_lat;

// String control
// Should use %0s
reg[9*8:1]  reset_color       = "\033[1;0m";
reg[10*8:1] txt_black_prefix  = "\033[1;30m";
reg[10*8:1] txt_red_prefix    = "\033[1;31m";
reg[10*8:1] txt_green_prefix  = "\033[1;32m";
reg[10*8:1] txt_yellow_prefix = "\033[1;33m";
reg[10*8:1] txt_blue_prefix   = "\033[1;34m";

reg[10*8:1] bkg_black_prefix  = "\033[40;1m";
reg[10*8:1] bkg_red_prefix    = "\033[41;1m";
reg[10*8:1] bkg_green_prefix  = "\033[42;1m";
reg[10*8:1] bkg_yellow_prefix = "\033[43;1m";
reg[10*8:1] bkg_blue_prefix   = "\033[44;1m";
reg[10*8:1] bkg_white_prefix  = "\033[47;1m";

//=====================================================================
//      DATA MODEL
//=====================================================================
parameter NUM_OF_FRAME = 16;
parameter NUM_OF_PARAM_SETS = 16;
// Frame
parameter BITS_OF_PIXEL = 8;
parameter SIZE_OF_FRAME = 32;
parameter SIZE_OF_MACROBLOCK = 16;
parameter NUM_OF_MODE = 2;
parameter BITS_OF_QP = 5;
parameter MAX_OF_QP = 29;
// mode 0
parameter SIZE_OF_PREDICT_MODE_0 = 16;
// mode 1
parameter SIZE_OF_PREDICT_MODE_1 = 4;
// Operation
parameter SHIFT_T_L_MODE_0 = 5;
parameter SHIFT_T_MODE_0   = 4;
parameter SHIFT_L_MODE_0   = 4;
parameter SHIFT_T_L_MODE_1 = 3;
parameter SHIFT_T_MODE_1   = 2;
parameter SHIFT_L_MODE_1   = 2;
parameter DEFAULT_DC_VALUE = 128;

parameter SIZE_OF_TRANSFORM = 4;
parameter SHIFT_OF_INVERSE_TRANSFORM = 6;
parameter SIZE_OF_QUATIZATION = 4;
parameter NUM_TYPE_OF_QP = 6;
parameter SHIFT_OF_DEQUANTIZATION = 6;

reg[BITS_OF_PIXEL-1:0] _input_frame[NUM_OF_FRAME-1:0][SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // Input frame
reg _mode[SIZE_OF_FRAME/SIZE_OF_MACROBLOCK-1:0][SIZE_OF_FRAME/SIZE_OF_MACROBLOCK-1:0];
reg[BITS_OF_QP-1:0] _QP;
reg[BITS_OF_PIXEL-1:0] _your[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // Input frame
integer C[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0] = '{
    '{-1,  1,-1, 1}, // 15 ~ 12
    '{ 1, -1,-1, 1}, // 11 ~ 8
    '{-1, -1, 1, 1}, // 7 ~ 4
    '{ 1,  1, 1, 1} // 3 ~ 0
};
integer CT[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0] = '{
    '{-1,  1,-1, 1}, // 15 ~ 12
    '{ 1, -1,-1, 1}, // 11 ~ 8
    '{-1, -1, 1, 1}, // 7 ~ 4
    '{ 1,  1, 1, 1} // 3 ~ 0
};
integer qp_mf_a[0:NUM_TYPE_OF_QP-1] = '{13107,11916,10082,9362,8192,7282};
integer qp_mf_b[0:NUM_TYPE_OF_QP-1] = '{5243, 4660, 4194, 3647,3355,2893};
integer qp_mf_c[0:NUM_TYPE_OF_QP-1] = '{8066, 7490, 6554, 5825,5243,4559};
integer qp_offset[0:(MAX_OF_QP+1)/NUM_TYPE_OF_QP-1] = '{10922,21845,443690,87381,174762};
integer qp_v_a[0:NUM_TYPE_OF_QP-1] = '{10,11,13,14,16,18};
integer qp_v_b[0:NUM_TYPE_OF_QP-1] = '{16,18,20,23,25,29};
integer qp_v_c[0:NUM_TYPE_OF_QP-1] = '{13,14,16,18,20,23};
integer MF[SIZE_OF_QUATIZATION-1:0][SIZE_OF_QUATIZATION-1:0];
integer V[SIZE_OF_QUATIZATION-1:0][SIZE_OF_QUATIZATION-1:0];
integer offset;
integer qbits;

/*
input -> [macroblock partitioning] -------------------------[+]--> [+] ---------(X)---> [Integer transform] ---(W)---> [Quantization] ----(Z)---> [Pre-Entropy frame]
                                    |                               ^ [-]                                                                  |
                                    |                               |                                                                      |
                                    ---(I)-->[Intra Prediction]--->(P)                                                                     |
                                                    ^               |                                                                      |
                                                    | (R)       [+] v                                                                      |
                                                    ---------------[+] <--[+]---(X')-- [Integer transform] <---(W')-- [Dequantization] <--(Z)
*/
integer cur_index;
reg[NUM_OF_FRAME-1:0] index_flag;
// Forward
integer _frame_I[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // input -> [macroblock partitioning] -> I
integer _frame_P[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // I,R -> [Intra Prediction] -> P
integer _frame_X[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // X = I - P
integer _frame_W[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // X -> [Integer transform] -> W
integer _frame_Z[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // W -> [Quantization] -> Z
// Backward
integer _frame_W_inverse[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // Z -> [Dequantization] -> W_inverse
integer _frame_X_inverse[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // W_inverse -> [Integer transform] -> X_inverse
integer _frame_R[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0]; // R = P + X_inverse
// Other
reg[10*8:1] _prediction_mode[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _predict_dc[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _predict_v[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _predict_h[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _sad_frame_dc[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _sad_frame_v[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];
integer _sad_frame_h[SIZE_OF_FRAME-1:0][SIZE_OF_FRAME-1:0];


//=====================================================================
//  CLOCK
//=====================================================================
always	#(CYCLE/2.0) clk = ~clk; //clock

//=====================================================================
//  SIMULATION
//=====================================================================
initial exe_task;

task exe_task; begin
    reset_task;
    for (pat=0 ; pat<TOTAL_PATNUM ; pat=pat+1) begin
        generate_frames_task;
        input_frames_task;
        for (param_set=0 ; param_set<NUM_OF_FRAME ; param_set=param_set+1) begin
            clear_frames;
            generate_param_task;
            input_param_task;
            cal_task;
            wait_task;
            check_task;
        end
    end
    pass_task;
end endtask

task reset_task;begin
    force clk = 0;
    rst_n = 1;
    in_valid_data = 0;
    data = 'dx;
    in_valid_param = 0;
    index = 'dx;
    mode = 'dx;
    QP = 'dx;

    void'($urandom(SEED));
    total_lat = 0;

    #(CYCLE/2.0) rst_n = 0;
    #(CYCLE*3) rst_n = 1;
    if (out_valid !== 0 || out_value !== 0) begin
        display_full_seperator;
        $display("      Output signal should be 0 at %-12d ps  ", $time*1000);
        display_full_seperator;
        repeat(5) #(CYCLE);
        $finish;
    end
    #(CYCLE/2.0) release clk;
end endtask

task generate_frames_task;
    integer index,row,col;
begin
    for(index=0 ; index<NUM_OF_FRAME ; index=index+1) begin
        for(row=0 ; row<SIZE_OF_FRAME ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_FRAME ; col=col+1) begin
                _input_frame[index][row][col] = 
                    (pat < SIMPLE_PATNUM) ? $urandom() % 16 : $urandom() % (2**BITS_OF_PIXEL);
            end
        end
    end
    index_flag = 0;
end endtask

task input_frames_task;
    integer index,row,col;
begin
    repeat(($urandom() % 3) + 2) @(negedge clk);

    for(index=0 ; index<NUM_OF_FRAME ; index=index+1) begin
        for(row=0 ; row<SIZE_OF_FRAME ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_FRAME ; col=col+1) begin
                in_valid_data = 1;
                data = _input_frame[index][row][col];
                @(negedge clk);
            end
        end
    end
    in_valid_data = 0;
    data = 'dx;
end endtask

task generate_param_task;
    integer row, col;
    integer find_valid_index;
begin
    find_valid_index = 0;
    while(find_valid_index === 0) begin
        cur_index = $urandom() % NUM_OF_FRAME;
        if(index_flag[cur_index] === 0) begin
            index_flag[cur_index] = 1;
            find_valid_index = 1;
        end
    end
    for(row=0 ; row<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; col=col+1) begin
            _mode[row][col] = $urandom() % NUM_OF_MODE;
        end
    end
    _QP = $urandom() % (MAX_OF_QP+1);

    // Assign frame based on index
    for(row=0 ; row<SIZE_OF_FRAME ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME ; col=col+1) begin
            _frame_I[row][col] = _input_frame[cur_index][row][col];
        end
    end
end endtask

task input_param_task;
    integer row, col;
begin
    repeat(($urandom() % 3) + 2) @(negedge clk);

    for(row=0 ; row<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; col=col+1) begin
            in_valid_param = 1;
            if(row === 0 && col === 0) begin
                index = cur_index;
                QP = _QP;
            end
            else begin
                index = 'dx;
                QP = 'dx;
            end
            mode = _mode[row][col];
            @(negedge clk);
        end
    end
    in_valid_param = 0;
    index = 'dx;
    QP = 'dx;
    mode = 'dx;
end endtask

task cal_task;
    integer block_row,block_col;
    integer row,col;
    integer size;
begin
    if(_mode[0][0]===0) begin
        size = SIZE_OF_PREDICT_MODE_0;
    end
    else begin
        size = SIZE_OF_PREDICT_MODE_1;
    end

    for(block_row=0 ; block_row<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; block_row=block_row+1) begin
        for(block_col=0 ; block_col<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; block_col=block_col+1) begin
            if(_mode[block_row][block_col]===0) begin
                size = SIZE_OF_PREDICT_MODE_0;
            end
            else begin
                size = SIZE_OF_PREDICT_MODE_1;
            end

            for(row=0 ; row<SIZE_OF_MACROBLOCK/size ; row=row+1) begin
                for(col=0 ; col<SIZE_OF_MACROBLOCK/size ; col=col+1) begin
                    run_prediction(
                        block_row*SIZE_OF_MACROBLOCK + row*size,
                        block_col*SIZE_OF_MACROBLOCK + col*size,
                        size);

                    run_integer_transform(
                        block_row*SIZE_OF_MACROBLOCK + row*size,
                        block_col*SIZE_OF_MACROBLOCK + col*size,
                        size);

                    run_quantization(
                        block_row*SIZE_OF_MACROBLOCK + row*size,
                        block_col*SIZE_OF_MACROBLOCK + col*size,
                        size);

                    run_dequantization(
                        block_row*SIZE_OF_MACROBLOCK + row*size,
                        block_col*SIZE_OF_MACROBLOCK + col*size,
                        size);

                    run_inverse_integer_transform(
                        block_row*SIZE_OF_MACROBLOCK + row*size,
                        block_col*SIZE_OF_MACROBLOCK + col*size,
                        size);
                end
            end
        end
    end

    if(DEBUG===1) begin
        dump_input_frames_to_csv;
        dump_output_frames_to_csv;
    end
end endtask

task wait_task; begin
    execution_lat = -1;
    while (out_valid !== 1) begin
        if (out_value !== 0) begin
            display_full_seperator;
            $display("      Output signal should be 0 at %-12d ps  ", $time*1000);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
        if (execution_lat == MAX_EXECUTION_CYCLE) begin
            display_full_seperator;
            $display("      The execution latency at %-12d ps is over %5d cycles  ", $time*1000, MAX_EXECUTION_CYCLE);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish; 
        end
        execution_lat = execution_lat + 1;
        @(negedge clk);
    end
end endtask

task check_task;
    integer _max_out_lat;
    integer _out_lat;

    integer row;
    integer col;
    integer frame_row;
    integer frame_col;
    integer block_row;
    integer block_col;
    integer inner_row;
    integer inner_col;
begin
    // Output point should be in any order
    _out_lat = 0;
    _max_out_lat = SIZE_OF_FRAME*SIZE_OF_FRAME;

    frame_row = 0;
    frame_col = 0;
    block_row = 0;
    block_col = 0;
    inner_row = 0;
    inner_col = 0;
    while(_out_lat < _max_out_lat) begin
        wait_task;
        total_lat = total_lat + execution_lat;
        while(out_valid === 1) begin
            if (_out_lat===_max_out_lat) begin
                display_full_seperator;
                $display("      Out cycles is more than %-2d at %-12d ps ", _max_out_lat, $time*1000);
                display_full_seperator;
                repeat(5) @(negedge clk);
                $finish;
            end

            _your[frame_row*SIZE_OF_MACROBLOCK + block_row*4 + inner_row][frame_col*SIZE_OF_MACROBLOCK + block_col*4 + inner_col] = out_value;

            if( block_col === 4 - 1 &&
                block_row === 4 - 1 &&
                inner_col === 4 - 1 &&
                inner_row === 4 - 1) begin
                    frame_col = frame_col + 1;
                    if(frame_col === 2) begin
                        frame_col = 0;
                        frame_row = frame_row + 1;
                        if(frame_row === 2) begin
                            frame_row = 0;
                        end
                    end
            end

            if( inner_col === 4 - 1 &&
                inner_row === 4 - 1 ) begin
                    block_col = block_col + 1;
                    if(block_col === 4) begin
                        block_col = 0;
                        block_row = block_row + 1;
                        if(block_row === 4) begin
                            block_row = 0;
                        end
                    end
            end

            inner_col = inner_col + 1;
            if(inner_col === 4) begin
                inner_col = 0;
                inner_row = inner_row + 1;
                if(inner_row === 4) begin
                    inner_row = 0;
                end
            end

            _out_lat = _out_lat + 1;
            @(negedge clk);
        end
    end

    for(row=0 ; row<SIZE_OF_FRAME ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME ; col=col+1) begin
            if(_your[row][col] !== _frame_Z[row][col]) begin
                display_full_seperator;
                $display("      Output is not correct at (%2d, %2d) ", row, col);
                $display("      Your    : %4d ", _your[row][col]);
                $display("      Frame Z : %4d ", _frame_Z[row][col]);
                display_full_seperator;
                dump_input_frames_to_csv;
                dump_output_frames_to_csv;
                repeat(5) @(negedge clk);
                $finish;
            end
        end
    end

    $display("%0sPASS PATTERN NO.%4d, Parameter Set #%2d (Index %2d) %0sCycles: %3d%0s" ,txt_blue_prefix, pat, param_set, cur_index, txt_green_prefix, execution_lat, reset_color);
end endtask

task pass_task; begin
    $display("\033[1;33m                `oo+oy+`                            \033[1;35m Congratulation!!! \033[1;0m                                   ");
    $display("\033[1;33m               /h/----+y        `+++++:             \033[1;35m PASS This Lab........Maybe \033[1;0m                          ");
    $display("\033[1;33m             .y------:m/+ydoo+:y:---:+o             \033[1;35m Total Latency : %-10d\033[1;0m                                ", total_lat);
    $display("\033[1;33m              o+------/y--::::::+oso+:/y                                                                                     ");
    $display("\033[1;33m              s/-----:/:----------:+ooy+-                                                                                    ");
    $display("\033[1;33m             /o----------------/yhyo/::/o+/:-.`                                                                              ");
    $display("\033[1;33m            `ys----------------:::--------:::+yyo+                                                                           ");
    $display("\033[1;33m            .d/:-------------------:--------/--/hos/                                                                         ");
    $display("\033[1;33m            y/-------------------::ds------:s:/-:sy-                                                                         ");
    $display("\033[1;33m           +y--------------------::os:-----:ssm/o+`                                                                          ");
    $display("\033[1;33m          `d:-----------------------:-----/+o++yNNmms                                                                        ");
    $display("\033[1;33m           /y-----------------------------------hMMMMN.                                                                      ");
    $display("\033[1;33m           o+---------------------://:----------:odmdy/+.                                                                    ");
    $display("\033[1;33m           o+---------------------::y:------------::+o-/h                                                                    ");
    $display("\033[1;33m           :y-----------------------+s:------------/h:-:d                                                                    ");
    $display("\033[1;33m           `m/-----------------------+y/---------:oy:--/y                                                                    ");
    $display("\033[1;33m            /h------------------------:os++/:::/+o/:--:h-                                                                    ");
    $display("\033[1;33m         `:+ym--------------------------://++++o/:---:h/                                                                     ");
    $display("\033[1;31m        `hhhhhoooo++oo+/:\033[1;33m--------------------:oo----\033[1;31m+dd+                                                 ");
    $display("\033[1;31m         shyyyhhhhhhhhhhhso/:\033[1;33m---------------:+/---\033[1;31m/ydyyhs:`                                              ");
    $display("\033[1;31m         .mhyyyyyyhhhdddhhhhhs+:\033[1;33m----------------\033[1;31m:sdmhyyyyyyo:                                            ");
    $display("\033[1;31m        `hhdhhyyyyhhhhhddddhyyyyyo++/:\033[1;33m--------\033[1;31m:odmyhmhhyyyyhy                                            ");
    $display("\033[1;31m        -dyyhhyyyyyyhdhyhhddhhyyyyyhhhs+/::\033[1;33m-\033[1;31m:ohdmhdhhhdmdhdmy:                                           ");
    $display("\033[1;31m         hhdhyyyyyyyyyddyyyyhdddhhyyyyyhhhyyhdhdyyhyys+ossyhssy:-`                                                           ");
    $display("\033[1;31m         `Ndyyyyyyyyyyymdyyyyyyyhddddhhhyhhhhhhhhy+/:\033[1;33m-------::/+o++++-`                                            ");
    $display("\033[1;31m          dyyyyyyyyyyyyhNyydyyyyyyyyyyhhhhyyhhy+/\033[1;33m------------------:/ooo:`                                         ");
    $display("\033[1;31m         :myyyyyyyyyyyyyNyhmhhhyyyyyhdhyyyhho/\033[1;33m-------------------------:+o/`                                       ");
    $display("\033[1;31m        /dyyyyyyyyyyyyyyddmmhyyyyyyhhyyyhh+:\033[1;33m-----------------------------:+s-                                      ");
    $display("\033[1;31m      +dyyyyyyyyyyyyyyydmyyyyyyyyyyyyyds:\033[1;33m---------------------------------:s+                                      ");
    $display("\033[1;31m      -ddhhyyyyyyyyyyyyyddyyyyyyyyyyyhd+\033[1;33m------------------------------------:oo              `-++o+:.`             ");
    $display("\033[1;31m       `/dhshdhyyyyyyyyyhdyyyyyyyyyydh:\033[1;33m---------------------------------------s/            -o/://:/+s             ");
    $display("\033[1;31m         os-:/oyhhhhyyyydhyyyyyyyyyds:\033[1;33m----------------------------------------:h:--.`      `y:------+os            ");
    $display("\033[1;33m         h+-----\033[1;31m:/+oosshdyyyyyyyyhds\033[1;33m-------------------------------------------+h//o+s+-.` :o-------s/y  ");
    $display("\033[1;33m         m:------------\033[1;31mdyyyyyyyyymo\033[1;33m--------------------------------------------oh----:://++oo------:s/d  ");
    $display("\033[1;33m        `N/-----------+\033[1;31mmyyyyyyyydo\033[1;33m---------------------------------------------sy---------:/s------+o/d  ");
    $display("\033[1;33m        .m-----------:d\033[1;31mhhyyyyyyd+\033[1;33m----------------------------------------------y+-----------+:-----oo/h  ");
    $display("\033[1;33m        +s-----------+N\033[1;31mhmyyyyhd/\033[1;33m----------------------------------------------:h:-----------::-----+o/m  ");
    $display("\033[1;33m        h/----------:d/\033[1;31mmmhyyhh:\033[1;33m-----------------------------------------------oo-------------------+o/h  ");
    $display("\033[1;33m       `y-----------so /\033[1;31mNhydh:\033[1;33m-----------------------------------------------/h:-------------------:soo  ");
    $display("\033[1;33m    `.:+o:---------+h   \033[1;31mmddhhh/:\033[1;33m---------------:/osssssoo+/::---------------+d+//++///::+++//::::::/y+`  ");
    $display("\033[1;33m   -s+/::/--------+d.   \033[1;31mohso+/+y/:\033[1;33m-----------:yo+/:-----:/oooo/:----------:+s//::-.....--:://////+/:`    ");
    $display("\033[1;33m   s/------------/y`           `/oo:--------:y/-------------:/oo+:------:/s:                                                 ");
    $display("\033[1;33m   o+:--------::++`              `:so/:-----s+-----------------:oy+:--:+s/``````                                             ");
    $display("\033[1;33m    :+o++///+oo/.                   .+o+::--os-------------------:oy+oo:`/o+++++o-                                           ");
    $display("\033[1;33m       .---.`                          -+oo/:yo:-------------------:oy-:h/:---:+oyo                                          ");
    $display("\033[1;33m                                          `:+omy/---------------------+h:----:y+//so                                         ");
    $display("\033[1;33m                                              `-ys:-------------------+s-----+s///om                                         ");
    $display("\033[1;33m                                                 -os+::---------------/y-----ho///om                                         ");
    $display("\033[1;33m                                                    -+oo//:-----------:h-----h+///+d                                         ");
    $display("\033[1;33m                                                       `-oyy+:---------s:----s/////y                                         ");
    $display("\033[1;33m                                                           `-/o+::-----:+----oo///+s                                         ");
    $display("\033[1;33m                                                               ./+o+::-------:y///s:                                         ");
    $display("\033[1;33m                                                                   ./+oo/-----oo/+h                                          ");
    $display("\033[1;33m                                                                       `://++++syo`                                          ");
    $display("\033[1;0m"); 
    repeat(5) @(negedge clk);
    $finish;
end endtask

//=====================================================================
//  Algorithm : H.264 Lite
//=====================================================================
task clear_frames;
    integer row,col;
begin
    for(row=0 ; row<SIZE_OF_FRAME ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME ; col=col+1) begin
            _frame_I[row][col] = 'dx;
            _frame_P[row][col] = 'dx;
            _frame_X[row][col] = 'dx;
            _frame_W[row][col] = 'dx;
            _frame_Z[row][col] = 'dx;

            _frame_W_inverse[row][col] = 'dx;
            _frame_X_inverse[row][col] = 'dx;
            _frame_R[row][col] = 'dx;

            _prediction_mode[row][col] = "";
            _predict_dc[row][col] = 'dx;
            _predict_v[row][col] = 'dx;
            _predict_h[row][col] = 'dx;
            _sad_frame_dc[row][col] = 'dx;
            _sad_frame_v[row][col] = 'dx;
            _sad_frame_h[row][col] = 'dx;
        end
    end

    for(row=0 ; row<SIZE_OF_QUATIZATION ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_QUATIZATION ; col=col+1) begin
            MF[row][col] = 'dx;
        end
    end
    offset = 'dx;
    qbits = 'dx;
end endtask

task run_prediction;
    input integer row_start;
    input integer col_start;
    input integer size;

    integer row,col,inner;
    integer dc_value;
    integer shift;
    // SAD : sum of absolute difference
    integer sad_dc;
    integer sad_horizontal;
    integer sad_vertical;
begin
    // DC value
    dc_value = 0;
    if(row_start!==0) begin
        // T
        for(col=col_start ; col<col_start+size ; col=col+1) begin
            dc_value = dc_value + _frame_R[row_start-1][col];
        end
    end
    if(col_start!==0) begin
        // L
        for(row=row_start ; row<row_start+size ; row=row+1) begin
            dc_value = dc_value + _frame_R[row][col_start-1];
        end
    end
    // Shift
    if(row_start!==0 && col_start!==0) begin
        if(size === SIZE_OF_PREDICT_MODE_0)
            dc_value = dc_value >> SHIFT_T_L_MODE_0;
        else
            dc_value = dc_value >> SHIFT_T_L_MODE_1;
    end
    else if(row_start===0 && col_start===0) begin
        dc_value = DEFAULT_DC_VALUE;
    end
    else if(col_start===0) begin // T available
        if(size === SIZE_OF_PREDICT_MODE_0)
            dc_value = dc_value >> SHIFT_T_MODE_0;
        else
            dc_value = dc_value >> SHIFT_T_MODE_1;
    end
    else if(row_start===0) begin // L available
        if(size === SIZE_OF_PREDICT_MODE_0)
            dc_value = dc_value >> SHIFT_L_MODE_0;
        else
            dc_value = dc_value >> SHIFT_L_MODE_1;
    end
    

    // SAD : sum of absolute difference
    sad_dc = 0;
    sad_vertical = 2**31-1;
    sad_horizontal = 2**31-1;
    for(row=row_start ; row<row_start+size ; row=row+1) begin
        for(col=col_start ; col<col_start+size ; col=col+1) begin
            _predict_dc[row][col] = integer_abs(_frame_I[row][col] - dc_value);
            sad_dc = sad_dc + _predict_dc[row][col];
        end
    end
    _sad_frame_dc[row_start][col_start] = sad_dc;
    if(col_start!==0) begin
        for(row=row_start ; row<row_start+size ; row=row+1) begin
            for(col=col_start ; col<col_start+size ; col=col+1) begin
                _predict_h[row][col] = integer_abs(_frame_I[row][col] - _frame_R[row][col_start-1]);
                sad_horizontal = sad_horizontal + _predict_h[row][col];
            end
        end
        _sad_frame_h[row_start][col_start] = sad_horizontal;
    end
    if(row_start!==0) begin
        for(row=row_start ; row<row_start+size ; row=row+1) begin
            for(col=col_start ; col<col_start+size ; col=col+1) begin
                _predict_v[row][col] = integer_abs(_frame_I[row][col] - _frame_R[row_start-1][col]);
                sad_vertical = sad_vertical + _predict_v[row][col];
            end
        end
        _sad_frame_v[row_start][col_start] = sad_vertical;
    end

    // Assign prediction matirx : smallest SAD (same value -> follow DC > Horizontal > Vertical)
    _prediction_mode[row_start][col_start] = (sad_dc <= sad_horizontal && sad_dc <= sad_vertical) ? "DC" :
                                    (sad_horizontal <= sad_dc && sad_horizontal <= sad_vertical) ? "Horizontal" : "Vertical";
    for(row=row_start ; row<row_start+size ; row=row+1) begin
        for(col=col_start ; col<col_start+size ; col=col+1) begin
            _frame_P[row][col] = (sad_dc <= sad_horizontal && sad_dc <= sad_vertical) ? dc_value :
                                    (sad_horizontal <= sad_dc && sad_horizontal <= sad_vertical) ? _frame_R[row][col_start-1] : _frame_R[row_start-1][col];
            _frame_X[row][col] = _frame_I[row][col] - _frame_P[row][col];
        end
    end
end endtask

matrix_integer_multiplier #(
    SIZE_OF_TRANSFORM
) mm();

task run_integer_transform;
    input integer row_start;
    input integer col_start;
    input integer size;

    integer row1,col1;
    integer row2,col2;
    integer temp_out[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
    integer temp1[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
    integer temp2[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
begin
    if(size < SIZE_OF_TRANSFORM || (size%SIZE_OF_TRANSFORM) != 0) begin
        $display("[ERROR] Size (%3d) of integer transform should be divisible by %3d", size, SIZE_OF_TRANSFORM);
        $finish;
    end
    
    for(row1=0 ; row1<size/SIZE_OF_TRANSFORM ; row1=row1+1) begin
        for(col1=0 ; col1<size/SIZE_OF_TRANSFORM ; col1=col1+1) begin
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                    temp1[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM] = _frame_X[row_start+row2][col_start+col2];
                end
            end
            mm.multiple(temp2, C, temp1);
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                end
            end
            mm.multiple(temp_out, temp2, CT);
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                    _frame_W[row_start+row2][col_start+col2] = temp_out[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM];
                end
            end
        end
    end
end endtask

task run_quantization;
    input integer row_start;
    input integer col_start;
    input integer size;

    integer row1,col1;
    integer row2,col2;
    integer abs_value;
    integer sign_value;
begin
    for(row1=0 ; row1<SIZE_OF_QUATIZATION ; row1=row1+1) begin
        for(col1=0 ; col1<SIZE_OF_QUATIZATION ; col1=col1+1) begin
            if(row1===0 || row1===2) begin
                if(col1===0 || col1===2) begin
                    MF[row1][col1] = qp_mf_a[_QP%NUM_TYPE_OF_QP];
                end
                else if(col1===1 || col1===3) begin
                    MF[row1][col1] = qp_mf_c[_QP%NUM_TYPE_OF_QP];
                end
            end
            else if(row1===1 || row1===3) begin
                if(col1===0 || col1===2) begin
                    MF[row1][col1] = qp_mf_c[_QP%NUM_TYPE_OF_QP];
                end
                else if(col1===1 || col1===3) begin
                    MF[row1][col1] = qp_mf_b[_QP%NUM_TYPE_OF_QP];
                end
            end
        end
    end
    offset = qp_offset[_QP/NUM_TYPE_OF_QP];
    qbits = 15 + $floor(_QP/NUM_TYPE_OF_QP);

    for(row1=0 ; row1<size/SIZE_OF_QUATIZATION ; row1=row1+1) begin
        for(col1=0 ; col1<size/SIZE_OF_QUATIZATION ; col1=col1+1) begin
            for(row2=row1*SIZE_OF_QUATIZATION ; row2<(row1+1)*SIZE_OF_QUATIZATION ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_QUATIZATION ; col2<(col1+1)*SIZE_OF_QUATIZATION ; col2=col2+1) begin
                    abs_value = integer_abs(_frame_W[row_start+row2][col_start+col2]);
                    abs_value = (abs_value * MF[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM] + offset) >> qbits;
                    sign_value = _frame_W[row_start+row2][col_start+col2] > 0 ? 1 : -1;
                    _frame_Z[row_start+row2][col_start+col2] = abs_value * sign_value;
                end
            end
        end
    end
end endtask

task run_dequantization;
    input integer row_start;
    input integer col_start;
    input integer size;

    integer row1,col1;
    integer row2,col2;
    integer value;
begin
    for(row1=0 ; row1<SIZE_OF_QUATIZATION ; row1=row1+1) begin
        for(col1=0 ; col1<SIZE_OF_QUATIZATION ; col1=col1+1) begin
            if(row1===0 || row1===2) begin
                if(col1===0 || col1===2) begin
                    V[row1][col1] = qp_v_a[_QP%NUM_TYPE_OF_QP];
                end
                else if(col1===1 || col1===3) begin
                    V[row1][col1] = qp_v_c[_QP%NUM_TYPE_OF_QP];
                end
            end
            else if(row1===1 || row1===3) begin
                if(col1===0 || col1===2) begin
                    V[row1][col1] = qp_v_c[_QP%NUM_TYPE_OF_QP];
                end
                else if(col1===1 || col1===3) begin
                    V[row1][col1] = qp_v_b[_QP%NUM_TYPE_OF_QP];
                end
            end
        end
    end

    for(row1=0 ; row1<size/SIZE_OF_QUATIZATION ; row1=row1+1) begin
        for(col1=0 ; col1<size/SIZE_OF_QUATIZATION ; col1=col1+1) begin
            for(row2=row1*SIZE_OF_QUATIZATION ; row2<(row1+1)*SIZE_OF_QUATIZATION ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_QUATIZATION ; col2<(col1+1)*SIZE_OF_QUATIZATION ; col2=col2+1) begin
                    value = _frame_Z[row_start+row2][col_start+col2];
                    value = value * V[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM];
                    value = value * (2**$floor(_QP/NUM_TYPE_OF_QP));
                    _frame_W_inverse[row_start+row2][col_start+col2] = value;
                end
            end
        end
    end
end endtask

task run_inverse_integer_transform;
    input integer row_start;
    input integer col_start;
    input integer size;

    integer row1,col1;
    integer row2,col2;
    integer temp_out[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
    integer temp1[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
    integer temp2[SIZE_OF_TRANSFORM-1:0][SIZE_OF_TRANSFORM-1:0];
begin
    if(size < SIZE_OF_TRANSFORM || (size%SIZE_OF_TRANSFORM) != 0) begin
        $display("[ERROR] Size (%3d) of integer transform should be divisible by %3d", size, SIZE_OF_TRANSFORM);
        $finish;
    end
    
    for(row1=0 ; row1<size/SIZE_OF_TRANSFORM ; row1=row1+1) begin
        for(col1=0 ; col1<size/SIZE_OF_TRANSFORM ; col1=col1+1) begin
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                    temp1[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM] = _frame_W_inverse[row_start+row2][col_start+col2];
                end
            end
            mm.multiple(temp2, CT, temp1);
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                end
            end
            mm.multiple(temp_out, temp2, C);
            for(row2=row1*SIZE_OF_TRANSFORM ; row2<(row1+1)*SIZE_OF_TRANSFORM ; row2=row2+1) begin
                for(col2=col1*SIZE_OF_TRANSFORM ; col2<(col1+1)*SIZE_OF_TRANSFORM ; col2=col2+1) begin
                    _frame_X_inverse[row_start+row2][col_start+col2] = temp_out[row2%SIZE_OF_TRANSFORM][col2%SIZE_OF_TRANSFORM] >>> SHIFT_OF_INVERSE_TRANSFORM;
                    _frame_R[row_start+row2][col_start+col2] = _frame_X_inverse[row_start+row2][col_start+col2] + _frame_P[row_start+row2][col_start+col2];
                end
            end
        end
    end
end endtask

function integer integer_abs;
    input integer in;
begin
    integer_abs = in > 0 ? in : -in;
end
endfunction

//=====================================================================
// Debug
//=====================================================================
task display_full_seperator; begin
    // Full
    $system("printf '%*s\\n' `tput cols` '' | tr ' ' '='");
    // Half
    // $system("cols=`tput cols`; half=$((cols/2-6)); printf '%*s\\n' $half ''");
end endtask

matrix_2d_csv_dumper #(
    SIZE_OF_FRAME-1,SIZE_OF_FRAME-1,
    0,0,
    BITS_OF_PIXEL) frame_dumper();

matrix_string_2d_csv_dumper #(
    SIZE_OF_FRAME-1,SIZE_OF_FRAME-1,
    0,0,
    10*8) string_dumper();

matrix_integer_2d_csv_dumper #(
    SIZE_OF_FRAME-1,SIZE_OF_FRAME-1,
    0,0) integer_dumper();

matrix_integer_2d_csv_dumper #(
    SIZE_OF_QUATIZATION-1,SIZE_OF_QUATIZATION-1,
    0,0) mf_dumper();

matrix_3d_csv_dumper #(
    3,SIZE_OF_FRAME-1,SIZE_OF_FRAME-1,
    0,0,0,
    BITS_OF_PIXEL) input_dumper();

task dump_input_frames_to_csv;
    integer file;
    integer indx;
begin
    file = $fopen(INPUT_CSV, "w");
    for(index=0 ; index<NUM_OF_FRAME/4 ; index=index+1) begin
        $fdisplay(file, "[%2d] ~ [%2d],", index*4, (index+1)*4-1);
        input_dumper.dump(file, _input_frame[index*4+:4]);
        $fdisplay(file, ",");
    end
    $fclose(file);
end endtask

task dump_output_frames_to_csv;
    integer file;
    integer row,col;
begin
    file = $fopen(OUTPUT_CSV, "w");
    $fdisplay(file, "QP,%2d", _QP);
    $fwrite(file, "Mode,");
    for(row=0 ; row<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; row=row+1) begin
        for(col=0 ; col<SIZE_OF_FRAME/SIZE_OF_MACROBLOCK ; col=col+1) begin
            $fwrite(file, "%2d,", _mode[row][col]);
        end
    end
    $fdisplay(file, "\n");
    $fdisplay(file, "Current Index,%2d",cur_index);
    integer_dumper.dump_with_seperator(file, _frame_I, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Prediction");
    integer_dumper.dump_with_seperator(file, _frame_P, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "Prediction,Mode");
    string_dumper.dump_with_seperator(file, _prediction_mode, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "");
    $fdisplay(file, "Prediction,DC Value");
    integer_dumper.dump_with_seperator(file, _predict_dc, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Prediction,Horizontal Value");
    integer_dumper.dump_with_seperator(file, _predict_h, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Prediction,Vertical Value");
    integer_dumper.dump_with_seperator(file, _predict_v, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "Prediction,SAD DC Value");
    integer_dumper.dump_with_seperator(file, _sad_frame_dc, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Prediction,SAD Horizontal Value");
    integer_dumper.dump_with_seperator(file, _sad_frame_h, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Prediction,SAD Vertical Value");
    integer_dumper.dump_with_seperator(file, _sad_frame_v, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "");
    $fdisplay(file, "Frame X");
    integer_dumper.dump_with_seperator(file, _frame_X, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Frame W");
    integer_dumper.dump_with_seperator(file, _frame_W, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "");
    $fdisplay(file, "MF Matrix");
    mf_dumper.dump(file, MF);
    $fdisplay(file, "");
    $fdisplay(file, "Quantization Offset,%6d", offset);
    $fdisplay(file, "");
    $fdisplay(file, "Quantization Bits,%2d", qbits);
    $fdisplay(file, "");
    $fdisplay(file, "Frame Z");
    integer_dumper.dump_with_seperator(file, _frame_Z, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Your");
    frame_dumper.dump_with_seperator(file, _your, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "");
    $fdisplay(file, "V Matrix");
    mf_dumper.dump(file, V);
    $fdisplay(file, "");
    $fdisplay(file, "Frame W'");
    integer_dumper.dump_with_seperator(file, _frame_W_inverse, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fdisplay(file, "");
    $fdisplay(file, "Frame X'");
    integer_dumper.dump_with_seperator(file, _frame_X_inverse, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");
    $fdisplay(file, "Frame R");
    integer_dumper.dump_with_seperator(file, _frame_R, SIZE_OF_MACROBLOCK, SIZE_OF_MACROBLOCK);
    $fdisplay(file, "");

    $fclose(file);
end endtask

endmodule

//==========================================================================================================================================
// Helper
//==========================================================================================================================================
module matrix_integer_multiplier
#(
    parameter size = 1
)();
integer row,col,inner;

initial begin
    if(size < 0) begin
        $display("[ERROR] Size (%3d) should be larger than 0", size);
        $finish;
    end
end

task multiple;
    output integer R[size-1:0][size-1:0];
    input integer A[size-1:0][size-1:0];
    input integer B[size-1:0][size-1:0];
begin
    for(row=0 ; row<size ; row=row+1) begin
        for(col=0 ; col<size ; col=col+1) begin
            R[row][col] = 0;
            for(inner=0 ; inner<size ; inner=inner+1) begin
                R[row][col] = R[row][col] + (A[row][inner] * B[inner][col]);
            end
        end
    end
end endtask
endmodule


//==========================================================================================================================================
// Dumper
//==========================================================================================================================================
module matrix_2d_csv_dumper
#(
    parameter end1 = 0,
    parameter end2 = 0,
    parameter start1 = 0,
    parameter start2 = 0,
    parameter num_of_bits = 0,
    parameter seperator = "",
    parameter prefix_col = "",
    parameter postfix_col = "",
    parameter prefix_row = "",
    parameter postfix_row = ""
)();
integer idx1,idx2;

task dump; 
    input integer file;
    input [num_of_bits-1:0] in[end1:start1][end2:start2];
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            $fwrite(file, "%8d,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;

task dump_with_seperator; 
    input integer file;
    input [num_of_bits-1:0] in[end1:start1][end2:start2];
    input integer num1;
    input integer num2;
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        if(idx2!==start2 && idx2%num2===0)
            $fwrite(file, "%0s,", seperator);
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        if(idx1!==start1 && idx1%num1===0)
            $fwrite(file, "\n");
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            if(idx2!==start2 && idx2%num2===0)
                $fwrite(file, "%0s,", seperator);
            $fwrite(file, "%8d,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;
endmodule

module matrix_string_2d_csv_dumper
#(
    parameter end1 = 0,
    parameter end2 = 0,
    parameter start1 = 0,
    parameter start2 = 0,
    parameter num_of_bits = 1,
    parameter seperator = "",
    parameter prefix_col = "",
    parameter postfix_col = "",
    parameter prefix_row = "",
    parameter postfix_row = ""
)();
integer idx1,idx2;

task dump; 
    input integer file;
    input reg[num_of_bits:1] in[end1:start1][end2:start2];
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            $fwrite(file, "%0s,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;

task dump_with_seperator; 
    input integer file;
    input reg[num_of_bits:1] in[end1:start1][end2:start2];
    input integer num1;
    input integer num2;
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        if(idx2!==start2 && idx2%num2===0)
            $fwrite(file, "%0s,", seperator);
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        if(idx1!==start1 && idx1%num1===0)
            $fwrite(file, "\n");
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            if(idx2!==start2 && idx2%num2===0)
                $fwrite(file, "%0s,", seperator);
            $fwrite(file, "%0s,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;
endmodule

module matrix_integer_2d_csv_dumper
#(
    parameter end1 = 0,
    parameter end2 = 0,
    parameter start1 = 0,
    parameter start2 = 0,
    parameter seperator = "",
    parameter prefix_col = "",
    parameter postfix_col = "",
    parameter prefix_row = "",
    parameter postfix_row = ""
)();
integer idx1,idx2;

task dump; 
    input integer file;
    input integer in[end1:start1][end2:start2];
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            $fwrite(file, "%8d,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;

task dump_with_seperator; 
    input integer file;
    input integer in[end1:start1][end2:start2];
    input integer num1;
    input integer num2;
begin
    $fwrite(file, ",");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        if(idx2!==start2 && idx2%num2===0)
            $fwrite(file, "%0s,", seperator);
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx2, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        if(idx1!==start1 && idx1%num1===0)
            $fwrite(file, "\n");
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx1, postfix_row);
        for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
            if(idx2!==start2 && idx2%num2===0)
                $fwrite(file, "%0s,", seperator);
            $fwrite(file, "%8d,", in[idx1][idx2]);
        end
        $fwrite(file, "\n");
    end
end endtask;

endmodule

module matrix_3d_csv_dumper
#(
    parameter end1 = 0,
    parameter end2 = 0,
    parameter end3 = 0,
    parameter start1 = 0,
    parameter start2 = 0,
    parameter start3 = 0,
    parameter num_of_bits = 0,
    parameter prefix_index = "",
    parameter postfix_index = "",
    parameter prefix_col = "",
    parameter postfix_col = "",
    parameter prefix_row = "",
    parameter postfix_row = ""
)();
integer idx1,idx2,idx3;

task dump; 
    input integer file;
    input [num_of_bits-1:0] in[end1:start1][end2:start2][end3:start3];
begin
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "[%0s%2d%0s],", prefix_index, idx1, postfix_index);
        // idx1 index
        for(idx3=start3 ; idx3<=end3 ; idx3=idx3+1) begin
            $fwrite(file, "%0s%2d%0s,", prefix_col, idx3, postfix_col);
        end
        $fwrite(file, ",");
    end
    $fwrite(file, "\n");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
            // idx2 index and value
            $fwrite(file, "%0s%2d%0s,", prefix_row, idx2, postfix_row);
            for(idx3=start3 ; idx3<=end3 ; idx3=idx3+1) begin
                $fwrite(file, "%8d,", in[idx1][idx2][idx3]);
            end
            $fwrite(file, ",");
        end
        $fwrite(file, "\n");
    end
end endtask;
endmodule