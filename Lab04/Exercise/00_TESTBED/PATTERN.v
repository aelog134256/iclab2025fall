`define CYCLE_TIME 45.0

module PATTERN(
    // Output Port
    clk,
    rst_n,
    in_valid,
    Image,
    Kernel_ch1,
    Kernel_ch2,
	Weight_Bias,
    task_number,
    mode,
    capacity_cost,
    // Input Port
    out_valid,
    out
    );

//=====================================================================
//   PORT DECLARATION
//=====================================================================
output reg         clk, rst_n, in_valid;
output reg [31:0]  Image;
output reg [31:0]  Kernel_ch1;
output reg [31:0]  Kernel_ch2;
output reg [31:0]  Weight_Bias;
output reg         task_number;
output reg [1:0]   mode;
output reg [3:0]   capacity_cost;

input           out_valid;
input   [31:0]  out;

//=====================================================================
//   PARAMETER & INTEGER DECLARATION
//=====================================================================
//vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
// Can be modified by user
integer   TOTAL_PATNUM = 100;
integer   SIMPLE_PATNUM = 100;
// >>>>> General Pattern Parameter
// @Why need this
//      Prevent the final outcome become NaN or Infinite
// Make sure the number should be with decimal point XXX.0
real      MIN_RANGE_OF_INPUT = -0.5;
real      MAX_RANGE_OF_INPUT = 0.5;
// parameter PRECISION_OF_RANDOM_EXPONENT = -5; // 2^(PRECISION_OF_RANDOM_EXPONENT) ~ the exponent of MAX_RANGE_OF_INPUT
// <<<<< General Pattern Parameter
integer   SEED = 5487;
parameter DEBUG = 1;
parameter DEBUG_ASSIGN_TASK = 1; // Only for DEBUG = 2
parameter DEBUG_ASSIGN_MODE = 0; // Only for DEBUG = 2
parameter INPUT_HEX_CSV = "input_hex.csv";
parameter INPUT_FLOAT_CSV = "input_float.csv";
parameter OUTPUT_HEX_CSV = "output_hex.csv";
parameter OUTPUT_FLOAT_CSV = "output_float.csv";
//^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
real      CYCLE = `CYCLE_TIME;
parameter MAX_EXECUTION_CYCLE = 150;

parameter inst_sig_width = 23;
parameter inst_exp_width = 8;
parameter inst_ieee_compliance = 0;
parameter inst_arch_type = 0;
parameter inst_arch = 0;
parameter real_sig_width = 52; // verilog real (double)
parameter real_exp_width = 11; // verilog real (double)

// PATTERN control
integer pat;
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
// Parameter
real RAND_DIVISOR = (2.0**32) - 1.0;
// Input
parameter NUM_OF_TASK = 2;
parameter NUM_OF_MODE = 4;

parameter MAX_NUM_OF_IMAGE = 2;
parameter NUM_OF_IMAGE_TASK0 = 2;
parameter NUM_OF_IMAGE_TASK1 = 1;
parameter SIZE_OF_IMAGE = 6;

parameter NUM_OF_KERNEL_CH = 2;
parameter NUM_OF_KERNEL_IN_CH = 2;
parameter SIZE_OF_KERNEL = 3;
// Input : task 0
parameter NUM_OF_WEIGHT1 = 5;
parameter SIZE_OF_WEIGHT1 = 8;
parameter NUM_OF_BIAS1 = 1;
parameter NUM_OF_WEIGHT2 = 3;
parameter SIZE_OF_WEIGHT2 = 5;
parameter NUM_OF_BIAS2 = 1;
// Input : task 1
parameter NUM_OF_CAPACITY = 5;
parameter BITS_OF_CAPACITY = 4;

// Output
parameter SIZE_OF_PAD_WINDOW = 2;
parameter SIZE_OF_PAD = SIZE_OF_IMAGE + SIZE_OF_PAD_WINDOW; // 6 + 2 = 8
parameter SIZE_OF_CONV = SIZE_OF_PAD - SIZE_OF_KERNEL + 1; // 8 - 3 + 1 = 6
// Output : task 0
parameter SIZE_OF_MAXPOOL_WINDOW = 3;
parameter SIZE_OF_MAXPOOL = SIZE_OF_CONV / SIZE_OF_MAXPOOL_WINDOW; // 2
parameter SIZE_OF_ACTIVATE = SIZE_OF_MAXPOOL; // 2
parameter NUM_OF_FULLY1 = NUM_OF_WEIGHT1; // 5
parameter SIZE_OF_FULLY1 = SIZE_OF_WEIGHT1; // = NUM_OF_KERNEL_CH*SIZE_OF_ACTIVATE*SIZE_OF_ACTIVATE = 2 * 2 * 2 = 8
parameter NUM_OF_FULLY2 = NUM_OF_WEIGHT2; // 3
parameter SIZE_OF_FULLY2 = SIZE_OF_WEIGHT2; // = NUM_OF_WEIGHT1 = 5
parameter SIZE_OF_SOFTMAX = NUM_OF_FULLY2;
parameter NUM_OF_OUTPUT_TASK0 = SIZE_OF_SOFTMAX;

// Output : task 1
parameter SIZE_OF_CONV_SUM = NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_IN_CH; // 4
parameter NUM_OF_OUTPUT_TASK1 = 1;
//-------------------------------------------------------------------------------------------------------------------------------------

// Data
// Input
reg _task_number;
reg[1:0] _mode;
reg[1:0] _cur_num_of_image;
reg[1:0] _cur_num_of_output;
reg[inst_sig_width+inst_exp_width:0] _img[MAX_NUM_OF_IMAGE-1:0][SIZE_OF_IMAGE-1:0][SIZE_OF_IMAGE-1:0];
reg[inst_sig_width+inst_exp_width:0] _kernel[NUM_OF_KERNEL_CH:1][NUM_OF_KERNEL_IN_CH:1][SIZE_OF_KERNEL-1:0][SIZE_OF_KERNEL-1:0];
// Input : task 0
reg[inst_sig_width+inst_exp_width:0] _weight1[NUM_OF_WEIGHT1-1:0][SIZE_OF_WEIGHT1-1:0];
reg[inst_sig_width+inst_exp_width:0] _bias1[NUM_OF_BIAS1-1:0];
reg[inst_sig_width+inst_exp_width:0] _weight2[NUM_OF_WEIGHT2-1:0][SIZE_OF_WEIGHT2-1:0];
reg[inst_sig_width+inst_exp_width:0] _bias2[NUM_OF_BIAS2-1:0];
// Input : task 1
reg[BITS_OF_CAPACITY-1:0] _capacity[NUM_OF_CAPACITY-1:0];

//-------------------------------------------------------------------------------------------------------------------------------------

// Result
reg[inst_sig_width+inst_exp_width:0] _pad[MAX_NUM_OF_IMAGE-1:0][SIZE_OF_PAD-1:0][SIZE_OF_PAD-1:0];
// Result : task 0
wire[inst_sig_width+inst_exp_width:0] _convolution0_w[NUM_OF_KERNEL_CH-1:0][NUM_OF_KERNEL_IN_CH:1][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
reg[inst_sig_width+inst_exp_width:0]  _convolution0  [NUM_OF_KERNEL_CH-1:0][NUM_OF_KERNEL_IN_CH:1][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
wire[inst_sig_width+inst_exp_width:0] _convolution0_sum_w[NUM_OF_KERNEL_CH-1:0][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
reg[inst_sig_width+inst_exp_width:0]  _convolution0_sum  [NUM_OF_KERNEL_CH-1:0][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
//
wire[inst_sig_width+inst_exp_width:0] _max_pool_w[NUM_OF_KERNEL_CH-1:0][SIZE_OF_MAXPOOL-1:0][SIZE_OF_MAXPOOL-1:0];
reg[inst_sig_width+inst_exp_width:0]  _max_pool  [NUM_OF_KERNEL_CH-1:0][SIZE_OF_MAXPOOL-1:0][SIZE_OF_MAXPOOL-1:0];
//
wire[inst_sig_width+inst_exp_width:0] _activation_w[NUM_OF_KERNEL_CH-1:0][SIZE_OF_ACTIVATE-1:0][SIZE_OF_ACTIVATE-1:0];
reg[inst_sig_width+inst_exp_width:0]  _activation  [NUM_OF_KERNEL_CH-1:0][SIZE_OF_ACTIVATE-1:0][SIZE_OF_ACTIVATE-1:0];
//
wire[inst_sig_width+inst_exp_width:0] _fully1_w[NUM_OF_FULLY1-1:0];
reg[inst_sig_width+inst_exp_width:0]  _fully1  [NUM_OF_FULLY1-1:0];
wire[inst_sig_width+inst_exp_width:0] _fully1_activated_w[NUM_OF_FULLY1-1:0];
reg[inst_sig_width+inst_exp_width:0]  _fully1_activated  [NUM_OF_FULLY1-1:0];
//
wire[inst_sig_width+inst_exp_width:0] _fully2_w[NUM_OF_FULLY2-1:0];
reg[inst_sig_width+inst_exp_width:0]  _fully2  [NUM_OF_FULLY2-1:0];
//
wire[inst_sig_width+inst_exp_width:0] _softmax_w[SIZE_OF_SOFTMAX-1:0];
reg[inst_sig_width+inst_exp_width:0]  _softmax  [SIZE_OF_SOFTMAX-1:0];
//
reg[inst_sig_width+inst_exp_width:0] _your_task0_output[NUM_OF_OUTPUT_TASK0-1:0];
wire [inst_sig_width+inst_exp_width:0] _err_allow = 32'h358637bd; // 0.000001
wire [inst_sig_width+inst_exp_width:0] _err_diff_w[NUM_OF_OUTPUT_TASK0-1:0];
reg  [inst_sig_width+inst_exp_width:0] _err_diff  [NUM_OF_OUTPUT_TASK0-1:0]; // |ans - gold|
wire _err_flag_w[NUM_OF_OUTPUT_TASK0-1:0]; // if the float of |ans - gold| is less than 0.000001 or not
reg  _err_flag  [NUM_OF_OUTPUT_TASK0-1:0];
reg _is_err;

// Result : task 1
wire[inst_sig_width+inst_exp_width:0] _convolution1_w[NUM_OF_IMAGE_TASK1-1:0][NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_CH:1][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
reg[inst_sig_width+inst_exp_width:0]  _convolution1  [NUM_OF_IMAGE_TASK1-1:0][NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_CH:1][SIZE_OF_CONV-1:0][SIZE_OF_CONV-1:0];
wire[inst_sig_width+inst_exp_width:0] _convolution1_sum_w[NUM_OF_IMAGE_TASK1-1:0][SIZE_OF_CONV_SUM-1:0];
reg[inst_sig_width+inst_exp_width:0]  _convolution1_sum  [NUM_OF_IMAGE_TASK1-1:0][SIZE_OF_CONV_SUM-1:0];
// TODO : Change to IP?
// DP
real _dp [NUM_OF_IMAGE_TASK1-1:0][(2**BITS_OF_CAPACITY-1):0];
reg[inst_sig_width+inst_exp_width:0] _select_channels[NUM_OF_IMAGE_TASK1-1:0][(2**BITS_OF_CAPACITY-1):0];

//-------------------------------------------------------------------------------------------------------------------------------------

//=====================================================================
//  CLOCK
//=====================================================================
initial clk = 1'b0;
always #(CYCLE/2.0) clk = ~clk;

//=====================================================================
//  SIMULATION
//=====================================================================
initial exe_task;

task exe_task; begin
    reset_task;
    for (pat=0 ; pat<TOTAL_PATNUM ; pat=pat+1) begin
        pre_generate_input_task;
        cal_task;
        post_fix_input_task;
        cal_task;
        input_task;
        wait_task;
        check_task;
    end
    pass_task;
end endtask

task reset_task; begin
    force clk = 0;
    rst_n = 1;
    in_valid = 0;
    task_number = 'dx;
    mode = 'dx;
    Image = 'dx;
    Kernel_ch1 = 'dx;
    Kernel_ch2 = 'dx;
    Weight_Bias = 'dx;
    capacity_cost = 'dx;

    void'($urandom(SEED));
    total_lat = 0;

    #(CYCLE/2.0) rst_n = 0;
    #(CYCLE/2.0) rst_n = 1;
    if (out_valid !== 0 || out !== 0) begin
        display_full_seperator;
        $display("      Output signal should be 0 at %-12d ps  ", $time*1000);
        display_full_seperator;
        repeat(5) #(CYCLE);
        $finish;
    end
    #(CYCLE/2.0) release clk;
end endtask

task clear_data;
    integer channel,num,row,col;
begin
    // Image
    for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_IMAGE ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_IMAGE ; col=col+1) begin
                _img[num][row][col] = 'dx;
            end
        end
    end
    // Kernel
    for(channel=1 ; channel<=NUM_OF_KERNEL_CH ; channel=channel+1) begin
        for(num=1 ; num<=NUM_OF_KERNEL_IN_CH ; num=num+1) begin
            for(row=0 ; row<SIZE_OF_KERNEL ; row=row+1) begin
                for(col=0 ; col<SIZE_OF_KERNEL ; col=col+1) begin
                    _kernel[channel][num][row][col] = 'dx;
                end
            end
        end
    end
    // Weight
    for(num=0 ; num<NUM_OF_WEIGHT1 ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_WEIGHT1 ; row=row+1) begin
            _weight1[num][row] = 'dx;
        end
    end
    for(num=0 ; num<NUM_OF_BIAS1 ; num=num+1) begin
        _bias1[num] = 'dx;
    end
    for(num=0 ; num<NUM_OF_WEIGHT2 ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_WEIGHT2 ; row=row+1) begin
            _weight2[num][row] = 'dx;
        end
    end
    for(num=0 ; num<NUM_OF_BIAS2 ; num=num+1) begin
        _bias2[num] = 'dx;
    end
    // Capacity
    for(num=0 ; num<NUM_OF_CAPACITY ; num=num+1) begin
        _capacity[num] = 'dx;
    end
end endtask;

task randomize_input;
    integer channel,num,row,col;
    integer flag;
begin
    _task_number = $urandom() % NUM_OF_TASK;
    _mode = $urandom() % NUM_OF_MODE;
    if(DEBUG == 2) begin
        _task_number = DEBUG_ASSIGN_TASK;
        _mode = DEBUG_ASSIGN_MODE;
    end
    _cur_num_of_image = _task_number == 0 ? NUM_OF_IMAGE_TASK0 : NUM_OF_IMAGE_TASK1;
    _cur_num_of_output = _task_number == 0 ? NUM_OF_OUTPUT_TASK0 : NUM_OF_OUTPUT_TASK1;

    // Image
    for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_IMAGE ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_IMAGE ; col=col+1) begin
                _img[num][row][col] = generate_rand_input(pat < SIMPLE_PATNUM);
            end
        end
    end

    // Kernel
    for(channel=1 ; channel<=NUM_OF_KERNEL_CH ; channel=channel+1) begin
        for(num=1 ; num<=NUM_OF_KERNEL_IN_CH ; num=num+1) begin
            for(row=0 ; row<SIZE_OF_KERNEL ; row=row+1) begin
                for(col=0 ; col<SIZE_OF_KERNEL ; col=col+1) begin
                    _kernel[channel][num][row][col] = generate_rand_input(pat < SIMPLE_PATNUM);
                end
            end
        end
    end

    if(_task_number === 'd0) begin
        // Weight
        for(num=0 ; num<NUM_OF_WEIGHT1 ; num=num+1) begin
            for(row=0 ; row<SIZE_OF_WEIGHT1 ; row=row+1) begin
                _weight1[num][row] = generate_rand_input(pat < SIMPLE_PATNUM);
            end
        end
        for(num=0 ; num<NUM_OF_BIAS1 ; num=num+1) begin
            _bias1[num] = generate_rand_input(pat < SIMPLE_PATNUM);
        end
        for(num=0 ; num<NUM_OF_WEIGHT2 ; num=num+1) begin
            for(row=0 ; row<SIZE_OF_WEIGHT2 ; row=row+1) begin
                _weight2[num][row] = generate_rand_input(pat < SIMPLE_PATNUM);
            end
        end
        for(num=0 ; num<NUM_OF_BIAS2 ; num=num+1) begin
            _bias2[num] = generate_rand_input(pat < SIMPLE_PATNUM);
        end
    end
    else begin
        // Capacity
        for(num=0 ; num<NUM_OF_CAPACITY ; num=num+1) begin
            _capacity[num] = $urandom() % (2**BITS_OF_CAPACITY-1) + 1;
        end
    end
end endtask

task pre_generate_input_task; begin
    clear_data;
    randomize_input;
    record_pad;
end endtask

task record_pad;
    integer num;
    integer row;
    integer col;
begin
    for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_PAD ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_PAD ; col=col+1) begin
                _pad[num][row][col] = 0;
            end
        end
    end

    for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_IMAGE ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_IMAGE ; col=col+1) begin
                _pad[num][row+1][col+1] = _img[num][row][col];
            end
        end
    end

    if(_mode==='d0 || _mode==='d1) begin
        for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
            for(row=1 ; row<=SIZE_OF_PAD-1 ; row=row+1) begin
                _pad[num][row][0] = _img[num][row-1][0];
                _pad[num][row][SIZE_OF_PAD-1] = _img[num][row-1][SIZE_OF_IMAGE-1];
            end
            for(col=1 ; col<=SIZE_OF_PAD-1 ; col=col+1) begin
                _pad[num][0][col] = _img[num][0][col-1];
                _pad[num][SIZE_OF_PAD-1][col] = _img[num][SIZE_OF_IMAGE-1][col-1];
            end
            _pad[num][0][0] = _img[num][0][0];
            _pad[num][0][SIZE_OF_PAD-1] = _img[num][0][SIZE_OF_IMAGE-1];
            _pad[num][SIZE_OF_PAD-1][0] = _img[num][SIZE_OF_IMAGE-1][0];
            _pad[num][SIZE_OF_PAD-1][SIZE_OF_PAD-1] = _img[num][SIZE_OF_IMAGE-1][SIZE_OF_IMAGE-1];
        end
    end
    else begin
        for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
            for(row=1 ; row<=SIZE_OF_PAD-1 ; row=row+1) begin
                _pad[num][row][0] = _img[num][row-1][0+1];
                _pad[num][row][SIZE_OF_PAD-1] = _img[num][row-1][SIZE_OF_IMAGE-1-1];
            end
            for(col=1 ; col<=SIZE_OF_PAD-1 ; col=col+1) begin
                _pad[num][0][col] = _img[num][0+1][col-1];
                _pad[num][SIZE_OF_PAD-1][col] = _img[num][SIZE_OF_IMAGE-1-1][col-1];
            end
            _pad[num][0][0] = _img[num][0+1][0+1];
            _pad[num][0][SIZE_OF_PAD-1] = _img[num][0+1][SIZE_OF_IMAGE-1-1];
            _pad[num][SIZE_OF_PAD-1][0] = _img[num][SIZE_OF_IMAGE-1-1][0+1];
            _pad[num][SIZE_OF_PAD-1][SIZE_OF_PAD-1] = _img[num][SIZE_OF_IMAGE-1-1][SIZE_OF_IMAGE-1-1];
        end
    end
end endtask

// Task 0
task record_convolution0;
    integer num,kernel,row,col;
begin
    for(num=0 ; num<NUM_OF_KERNEL_CH ; num=num+1) begin
        for(kernel=1 ; kernel<=NUM_OF_KERNEL_IN_CH ; kernel=kernel+1) begin
            for(row=0 ; row<SIZE_OF_CONV ; row=row+1) begin
                for(col=0 ; col<SIZE_OF_CONV ; col=col+1) begin
                    _convolution0[num][kernel][row][col] = _convolution0_w[num][kernel][row][col];
                end
            end
        end
    end

    for(num=0 ; num<NUM_OF_KERNEL_CH ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_CONV ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_CONV ; col=col+1) begin
                _convolution0_sum[num][row][col] = _convolution0_sum_w[num][row][col];
            end
        end
    end
end endtask

task record_max_pool;
    integer num,row,col;
begin
    for(num=0 ; num<NUM_OF_KERNEL_CH ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_MAXPOOL ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_MAXPOOL ; col=col+1) begin
                _max_pool[num][row][col] = _max_pool_w[num][row][col];
            end
        end
    end
end endtask

task record_activate;
    integer num,row,col;
begin
    for(num=0 ; num<NUM_OF_KERNEL_CH ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_ACTIVATE ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_ACTIVATE ; col=col+1) begin
                _activation[num][row][col] = _activation_w[num][row][col];
            end
        end
    end
end endtask

task record_fully;
    integer num;
begin
    for(num=0 ; num<NUM_OF_FULLY1 ; num=num+1) begin
        _fully1[num] = _fully1_w[num];
        _fully1_activated[num] = _fully1_activated_w[num];
    end

    for(num=0 ; num<NUM_OF_FULLY2 ; num=num+1) begin
        _fully2[num] = _fully2_w[num];
    end
end endtask

task record_softmax;
    integer size;
begin
    for(size=0 ; size<SIZE_OF_SOFTMAX ; size=size+1) begin
        _softmax[size] = _softmax_w[size];
    end
end endtask

// Task 1
task record_convolution1;
    integer num,kernel,row,col;
begin
    for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
        for(kernel=1 ; kernel<=NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_CH ; kernel=kernel+1) begin
            for(row=0 ; row<SIZE_OF_CONV ; row=row+1) begin
                for(col=0 ; col<SIZE_OF_CONV ; col=col+1) begin
                    _convolution1[num][kernel][row][col] = _convolution1_w[num][kernel][row][col];
                end
            end
        end
    end

    for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
        for(kernel=0 ; kernel<SIZE_OF_CONV_SUM ; kernel=kernel+1) begin
            _convolution1_sum[num][kernel] = _convolution1_sum_w[num][kernel];
        end
    end
end endtask

task calculate_select_kernel;
    integer num, channel, cost, total_cost;
    real candidate;
begin
    for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
        for(cost=0 ; cost<=(2**BITS_OF_CAPACITY-1) ; cost=cost+1) begin
            _dp[num][cost] = 0;
            _select_channels[num][cost] = 0;
        end
    end

    total_cost = _capacity[0];
    for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
        for(channel=0 ; channel<SIZE_OF_CONV_SUM ; channel=channel+1) begin
            if(_capacity[channel+1]<=total_cost) begin
                for(cost=total_cost ; cost>=0 ; cost=cost-1) begin
                    if(cost>=_capacity[channel+1]) begin
                        candidate = _dp[num][cost - _capacity[channel+1]] + float_bits_to_real(_convolution1_sum[num][channel]);
                        if(candidate > _dp[num][cost]) begin
                            _dp[num][cost] = candidate;
                            _select_channels[num][cost] = _select_channels[num][cost - _capacity[channel+1]] | (1 << (SIZE_OF_CONV_SUM-1-channel));
                        end
                    end
                end
            end
        end
    end
end endtask

task cal_task; begin
    @(posedge clk);
    if(_task_number === 'd0) begin
        record_convolution0;
        record_max_pool;
        record_activate;
        record_fully;
        record_softmax;
    end
    else begin
        record_convolution1;
        calculate_select_kernel;
    end

    if(DEBUG > 0) begin
        export_input_to_csv(0);
        export_input_to_csv(1);
        export_output_to_csv(0);
        export_output_to_csv(1);
    end
    @(posedge clk);
end endtask

task post_fix_input_task;
    integer flag;
    integer num, kernel, kernel_num, channel, row, col;
begin
    /*
        Based on the spec, we need to do validation checks on the input data.
        If the values violate the spec, they must be regenerated randomly.
    */
    // @Task 1
    if(_task_number === 'd1) begin
        /*
            @Capacity
            @Description :
                There must exist a cost less than capacity
            @Workaround :
                Regnerate capcacity until it meet the spec
        */
        flag = 0;
        for(num=1 ; num<NUM_OF_CAPACITY ; num=num+1) begin
            flag = flag | (_capacity[num]<=_capacity[0]);
        end
        while(flag === 'd0) begin
            // Capacity
            for(num=0 ; num<NUM_OF_CAPACITY ; num=num+1) begin
                _capacity[num] = $urandom() % (2**BITS_OF_CAPACITY-1) + 1;
            end
            // Check
            for(num=1 ; num<NUM_OF_CAPACITY ; num=num+1) begin
                flag = flag | (_capacity[num]<=_capacity[0]);
            end
        end

        /*
            @Convolution Sum
            @Description :
                Every channel's sum shouldn't be zero.
            @Workaround :
                Regenerate image or kernel until it meet the spec
        */
        for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
            for(kernel=0 ; kernel<SIZE_OF_CONV_SUM ; kernel=kernel+1) begin
                if(_convolution1_sum[num][kernel] === 0) begin
                    flag = 0;
                    while(flag === 'd0) begin
                        // Input
                        for(row=0 ; row<SIZE_OF_IMAGE ; row=row+1) begin
                            for(col=0 ; col<SIZE_OF_IMAGE ; col=col+1) begin
                                _img[num][row][col] = generate_rand_input(pat < SIMPLE_PATNUM);
                            end
                        end
                        // Kernel
                        for(channel=1 ; channel<=NUM_OF_KERNEL_CH ; channel=channel+1) begin
                            for(kernel_num=1 ; kernel_num<=NUM_OF_KERNEL_IN_CH ; kernel_num=kernel_num+1) begin
                                for(row=0 ; row<SIZE_OF_KERNEL ; row=row+1) begin
                                    for(col=0 ; col<SIZE_OF_KERNEL ; col=col+1) begin
                                        _kernel[channel][kernel_num][row][col] = generate_rand_input(pat < SIMPLE_PATNUM);
                                    end
                                end
                            end
                        end
                        // Check
                        #0;
                        cal_task;
                        flag = (_convolution1_sum[num][kernel] !== 0) ? 1 : 0;
                    end
                end
            end
        end
    end
end endtask

task input_task;
    integer count;
    integer count_new;
    integer num,row,col;
begin
    repeat(($urandom() % 3) + 2) @(negedge clk);

    count = 0;
    for(num=0 ; num<_cur_num_of_image ; num=num+1) begin
        for(row=0 ; row<SIZE_OF_IMAGE ; row=row+1) begin
            for(col=0 ; col<SIZE_OF_IMAGE ; col=col+1) begin
                in_valid = 'd1;
                if(count === 'd0) begin
                    task_number = _task_number;
                    mode = _mode;
                end
                else begin
                    task_number = 'dx;
                    mode = 'dx;
                end

                Image = _img[num][row][col];
                
                if(count < NUM_OF_KERNEL_IN_CH*SIZE_OF_KERNEL*SIZE_OF_KERNEL) begin
                    Kernel_ch1 = _kernel[1][count/(SIZE_OF_KERNEL*SIZE_OF_KERNEL)+1][count%(SIZE_OF_KERNEL*SIZE_OF_KERNEL)/SIZE_OF_KERNEL][count%SIZE_OF_KERNEL];
                    Kernel_ch2 = _kernel[2][count/(SIZE_OF_KERNEL*SIZE_OF_KERNEL)+1][count%(SIZE_OF_KERNEL*SIZE_OF_KERNEL)/SIZE_OF_KERNEL][count%SIZE_OF_KERNEL];
                end
                else begin
                    Kernel_ch1 = 'dx;
                    Kernel_ch2 = 'dx;
                end

                if(_task_number === 'd0) begin
                    if(count < (NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1)) begin
                        Weight_Bias = _weight1[count/SIZE_OF_WEIGHT1][count%SIZE_OF_WEIGHT1];
                    end
                    else if(count < (NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1 + NUM_OF_BIAS1)) begin
                        count_new = count - NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1;
                        Weight_Bias = _bias1[count_new%NUM_OF_BIAS1];
                    end
                    else if(count < (NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1 + NUM_OF_BIAS1 + NUM_OF_WEIGHT2*SIZE_OF_WEIGHT2)) begin
                        count_new = count - NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1 - NUM_OF_BIAS1;
                        Weight_Bias = _weight2[count_new/SIZE_OF_WEIGHT2][count_new%SIZE_OF_WEIGHT2];
                    end
                    else if(count < (NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1 + NUM_OF_BIAS1 + NUM_OF_WEIGHT2*SIZE_OF_WEIGHT2 + NUM_OF_BIAS2)) begin
                        count_new = count - NUM_OF_WEIGHT1*SIZE_OF_WEIGHT1 - NUM_OF_BIAS1 - NUM_OF_WEIGHT2*SIZE_OF_WEIGHT2;
                        Weight_Bias = _bias2[count_new%NUM_OF_BIAS2];
                    end
                    else begin
                        Weight_Bias = 'dx;
                    end
                end
                else begin
                    if(count < NUM_OF_CAPACITY) begin
                        capacity_cost = _capacity[count];
                    end
                    else begin
                        capacity_cost = 'dx;
                    end
                end

                count = count + 1;
                @(negedge clk);
            end
        end
    end
    in_valid ='d0;
    task_number = 'dx;
    mode = 'dx;
    Image = 'dx;
    Kernel_ch1 = 'dx;
    Kernel_ch2 ='dx;
    Weight_Bias = 'dx;
    capacity_cost = 'dx;
end endtask

task wait_task; begin
    execution_lat = -1;
    while (out_valid !== 1) begin
        if (out !== 0) begin
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

task record_error;
    integer num;
begin
    _is_err = 0;
    for(num=0 ; num<NUM_OF_OUTPUT_TASK0 ; num=num+1) begin
        _err_diff[num] = _err_diff_w[num];
        _err_flag[num] = _err_flag_w[num];
        if(_err_flag[num]) begin
            _is_err = 1;
        end
    end
end endtask

task check_task;
    integer _max_out_lat;
    integer _out_lat;

    integer num;
begin
    // Output point should be in any order
    _out_lat = 0;
    _max_out_lat = _cur_num_of_output;
    while(out_valid === 1) begin
        if (_out_lat===_max_out_lat) begin
            display_full_seperator;
            $display("      Out cycles is more than %-2d at %-12d ps ", _max_out_lat, $time*1000);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end

        // Task 1
        if(_task_number === 'd1) begin
            if(out !== _select_channels[0][_capacity[0]]) begin
                display_full_seperator;
                $display("      Output signal : selected channel is not correct");
                $display("          Your : %d - %b", out[inst_sig_width+inst_exp_width:SIZE_OF_CONV_SUM], out[SIZE_OF_CONV_SUM-1:0]);
                $display("          Gold : %d - %b",
                    _select_channels[0][_capacity[0]][inst_sig_width+inst_exp_width:SIZE_OF_CONV_SUM],
                    _select_channels[0][_capacity[0]][SIZE_OF_CONV_SUM-1:0]);
                $display("          Sum  : %f", _dp[0][_capacity[0]]);
                display_full_seperator;
                export_input_to_csv(0);
                export_input_to_csv(1);
                export_output_to_csv(0);
                export_output_to_csv(1);
                repeat(5) @(negedge clk);
                $finish;
            end
        end
        else begin
            _your_task0_output[_out_lat] = out;
        end

        _out_lat = _out_lat + 1;
        @(negedge clk);
    end

    if (_out_lat < _max_out_lat) begin
        display_full_seperator;
        $display("      Out cycles is less than %-2d at %-12d ps ", _max_out_lat, $time*1000);
        display_full_seperator;
        repeat(5) @(negedge clk);
        $finish;
    end

    // Task 0
    if(_task_number === 'd0) begin
        record_error;
        if(_is_err) begin
            display_full_seperator;
            $display("      Output err is over %1.8f (%8h)", float_bits_to_real(_err_allow), _err_allow);
            for(num=0 ; num<NUM_OF_OUTPUT_TASK0 ; num=num+1) begin
                $display("          Err Difference : %8.7f / %8h", float_bits_to_real(_err_diff[num]), _err_diff[num]);
                $display("          Err Check      : %d", _err_flag[num]);
                $display("          Your           : %8.7f / %8h", float_bits_to_real(_your_task0_output[num]), _your_task0_output[num]);
                $display("          Gold           : %8.7f / %8h\n", float_bits_to_real(_softmax[num]), _softmax[num]);
            end
            export_input_to_csv(0);
            export_input_to_csv(1);
            export_output_to_csv(0);
            export_output_to_csv(1);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
    end

    total_lat = total_lat + execution_lat;
    $display("%0sPASS PATTERN NO.%4d, %0sCycles: %3d%0s",txt_blue_prefix, pat, txt_green_prefix, execution_lat, reset_color);
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
// IP Module Connection
//=====================================================================

// Task 0 : Convolution
parameter NUM_OF_INPUT_OF_CONV = SIZE_OF_KERNEL*SIZE_OF_KERNEL; // 3 * 3
genvar gen_i, gen_j, gen_k;
genvar gen_num, gen_ch, gen_knl, gen_row, gen_col, gen_inner;
generate
    for(gen_ch=1 ; gen_ch<=NUM_OF_KERNEL_CH ; gen_ch=gen_ch+1) begin
        for(gen_knl=1 ; gen_knl<=NUM_OF_KERNEL_IN_CH ; gen_knl=gen_knl+1) begin
            for(gen_row=0 ; gen_row<SIZE_OF_CONV ; gen_row=gen_row+1) begin
                for(gen_col=0 ; gen_col<SIZE_OF_CONV ; gen_col=gen_col+1) begin
                    wire [inst_sig_width+inst_exp_width:0] a[NUM_OF_INPUT_OF_CONV-1:0];
                    wire [inst_sig_width+inst_exp_width:0] b[NUM_OF_INPUT_OF_CONV-1:0];
                    wire [inst_sig_width+inst_exp_width:0] conv_out;
                    // Input
                    for(gen_i=0 ; gen_i<NUM_OF_INPUT_OF_CONV ; gen_i=gen_i+1) begin
                        assign a[gen_i] = _pad[gen_knl-1][gen_row+gen_i/SIZE_OF_KERNEL][gen_col+gen_i%SIZE_OF_KERNEL];
                        assign b[gen_i] = _kernel[gen_ch][gen_knl][gen_i/SIZE_OF_KERNEL][gen_i%SIZE_OF_KERNEL];
                    end
                    // IP
                    mac #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,NUM_OF_INPUT_OF_CONV)
                        c(
                            .in1(a), .in2(b), .out(conv_out)
                        );
                    assign _convolution0_w[gen_ch-1][gen_knl][gen_row][gen_col] = conv_out;
                end
            end
        end
    end
endgenerate

generate
    for(gen_num=0 ; gen_num<NUM_OF_KERNEL_CH ; gen_num=gen_num+1) begin : gb_num0
        for(gen_row=0 ; gen_row<SIZE_OF_CONV ; gen_row=gen_row+1) begin : gb_row0
            for(gen_col=0 ; gen_col<SIZE_OF_CONV ; gen_col=gen_col+1) begin : gb_col0
                for(gen_knl=2 ; gen_knl<=NUM_OF_KERNEL_IN_CH ; gen_knl=gen_knl+1) begin : gb_knl0
                    wire [inst_sig_width+inst_exp_width:0] conv_sum_out;
                    if(gen_knl===2) begin
                        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                            as(
                                .a(_convolution0_w[gen_num][gen_knl-1][gen_row][gen_col]),
                                .b(_convolution0_w[gen_num][gen_knl][gen_row][gen_col]),
                                .op(1'd0), .rnd(3'd0), .z(conv_sum_out)
                            );
                    end
                    else begin
                        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                            as(
                                .a(gb_num0[gen_num].gb_row0[gen_row].gb_col0[gen_col].gb_knl0[gen_knl-1].conv_sum_out),
                                .b(_convolution0_w[gen_num][gen_knl][gen_row][gen_col]),
                                .op(1'd0), .rnd(3'd0), .z(conv_sum_out)
                            );
                    end
                end
                assign _convolution0_sum_w[gen_num][gen_row][gen_col] = 
                    gb_num0[gen_num].gb_row0[gen_row].gb_col0[gen_col].gb_knl0[NUM_OF_KERNEL_IN_CH].conv_sum_out;
            end
        end
    end
endgenerate

// Task 0 : Max Pool
parameter NUM_OF_INPUT_OF_MAXPOOL = SIZE_OF_MAXPOOL_WINDOW*SIZE_OF_MAXPOOL_WINDOW; // 3 * 3
generate
    for(gen_num=0 ; gen_num<NUM_OF_KERNEL_CH ; gen_num=gen_num+1) begin
        for(gen_row=0 ; gen_row<SIZE_OF_MAXPOOL ; gen_row=gen_row+1) begin
            for(gen_col=0 ; gen_col<SIZE_OF_MAXPOOL ; gen_col=gen_col+1) begin
                wire [inst_sig_width+inst_exp_width:0] _in[NUM_OF_INPUT_OF_MAXPOOL-1:0];
                wire [inst_sig_width+inst_exp_width:0] _min;
                wire [inst_sig_width+inst_exp_width:0] _max;
                // Input
                for(gen_i=0 ; gen_i<NUM_OF_INPUT_OF_MAXPOOL ; gen_i=gen_i+1) begin
                    assign _in[gen_i] = 
                        _convolution0_sum_w[gen_num]
                            [gen_row*SIZE_OF_MAXPOOL_WINDOW+gen_i/SIZE_OF_MAXPOOL_WINDOW]
                            [gen_col*SIZE_OF_MAXPOOL_WINDOW+gen_i%SIZE_OF_MAXPOOL_WINDOW];
                end
                // IP
                findMinAndMax
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,NUM_OF_INPUT_OF_MAXPOOL)
                    f(
                        .in(_in),.min(_min),.max(_max)
                    );

                assign _max_pool_w[gen_num][gen_row][gen_col] = _max;
            end
        end
    end
endgenerate

// Task 0 : Activation
generate
    for(gen_num=0 ; gen_num<NUM_OF_KERNEL_CH ; gen_num=gen_num+1) begin
        for(gen_row=0 ; gen_row<SIZE_OF_ACTIVATE ; gen_row=gen_row+1) begin
            for(gen_col=0 ; gen_col<SIZE_OF_ACTIVATE ; gen_col=gen_col+1) begin
                wire[inst_sig_width+inst_exp_width:0] _tanh_out;
                wire[inst_sig_width+inst_exp_width:0] _swish;
                swish#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                    s(
                        .in(_max_pool_w[gen_num][gen_row][gen_col]),
                        .out(_swish)
                    );
                tanh#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                    t(
                        .in(_max_pool_w[gen_num][gen_row][gen_col]),
                        .out(_tanh_out)
                    );
                assign _activation_w[gen_num][gen_row][gen_col] = (_mode==='d1 || _mode==='d3) ? _swish : _tanh_out;
            end
        end
    end
endgenerate

// Task 0 : Fully Connected
parameter NUM_OF_INPUT_OF_FULLY1 = SIZE_OF_WEIGHT1; // 8
parameter NUM_OF_INPUT_OF_FULLY2 = SIZE_OF_WEIGHT2; // 5
genvar gen_wght;
generate
    // Fully 1
    for(gen_wght=0 ; gen_wght<NUM_OF_FULLY1 ; gen_wght=gen_wght+1) begin
        wire [inst_sig_width+inst_exp_width:0] a[NUM_OF_INPUT_OF_FULLY1-1:0];
        wire [inst_sig_width+inst_exp_width:0] b[NUM_OF_INPUT_OF_FULLY1-1:0];
        wire [inst_sig_width+inst_exp_width:0] fully1_out_pre_bias;
        wire [inst_sig_width+inst_exp_width:0] fully1_out;
        wire [inst_sig_width+inst_exp_width:0] fully1_out_activated;
        // Input
        for(gen_num=0 ; gen_num<NUM_OF_KERNEL_CH ; gen_num=gen_num+1) begin
            for(gen_row=0 ; gen_row<SIZE_OF_ACTIVATE ; gen_row=gen_row+1) begin
                for(gen_col=0 ; gen_col<SIZE_OF_ACTIVATE ; gen_col=gen_col+1) begin
                    assign a[gen_num*SIZE_OF_ACTIVATE*SIZE_OF_ACTIVATE + gen_row*SIZE_OF_ACTIVATE + gen_col]
                        = _activation_w[gen_num][gen_row][gen_col];
                    assign b[gen_num*SIZE_OF_ACTIVATE*SIZE_OF_ACTIVATE + gen_row*SIZE_OF_ACTIVATE + gen_col]
                        = _weight1[gen_wght][gen_num*SIZE_OF_ACTIVATE*SIZE_OF_ACTIVATE + gen_row*SIZE_OF_ACTIVATE + gen_col];
                end
            end
        end
        // IP
        mac #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,NUM_OF_INPUT_OF_FULLY1)
            c(
                .in1(a), .in2(b), .out(fully1_out_pre_bias)
            );
        DW_fp_addsub
            #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                A0 (.a(fully1_out_pre_bias), .b(_bias1[0]), .op(1'd0), .rnd(3'd0), .z(fully1_out));
        assign _fully1_w[gen_wght] = fully1_out;

        leakyRelu #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
            lr(
                .in(fully1_out), .out(fully1_out_activated)
            );
        assign _fully1_activated_w[gen_wght] = fully1_out_activated;
    end

    // Fully 2
    for(gen_wght=0 ; gen_wght<NUM_OF_FULLY2 ; gen_wght=gen_wght+1) begin
        wire [inst_sig_width+inst_exp_width:0] a[NUM_OF_INPUT_OF_FULLY2-1:0];
        wire [inst_sig_width+inst_exp_width:0] b[NUM_OF_INPUT_OF_FULLY2-1:0];
        wire [inst_sig_width+inst_exp_width:0] fully2_out_pre_bias;
        wire [inst_sig_width+inst_exp_width:0] fully2_out;
        // Input
        for(gen_num=0 ; gen_num<NUM_OF_INPUT_OF_FULLY2 ; gen_num=gen_num+1) begin
            assign a[gen_num]
                = _fully1_activated_w[gen_num];
            assign b[gen_num]
                = _weight2[gen_wght][gen_num];
        end
        // IP
        mac #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,NUM_OF_INPUT_OF_FULLY2)
            c(
                .in1(a), .in2(b), .out(fully2_out_pre_bias)
            );
        DW_fp_addsub
            #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                A0 (.a(fully2_out_pre_bias), .b(_bias2[0]), .op(1'd0), .rnd(3'd0), .z(fully2_out));
        assign _fully2_w[gen_wght] = fully2_out;
    end
endgenerate

// Task 0 : Softmax
generate
    wire[inst_sig_width+inst_exp_width:0] in_z[SIZE_OF_SOFTMAX-1:0];
    for(gen_num=0 ; gen_num<SIZE_OF_SOFTMAX ; gen_num=gen_num+1) begin
        assign in_z[gen_num] = _fully2_w[gen_num];
    end
    for(gen_num=0 ; gen_num<SIZE_OF_SOFTMAX ; gen_num=gen_num+1) begin
        wire[inst_sig_width+inst_exp_width:0] softmax_out;
        softmax #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,SIZE_OF_SOFTMAX)
            sm(
                .in_z(in_z[gen_num]),
                .in(in_z),
                .out(softmax_out)
            );
        assign _softmax_w[gen_num] = softmax_out;
    end
endgenerate

// Task 0 : Error
generate
    for(gen_num=0 ; gen_num<NUM_OF_OUTPUT_TASK0 ; gen_num=gen_num+1) begin
        // wire [inst_sig_width+inst_exp_width:0] bound;
        wire [inst_sig_width+inst_exp_width:0] error_diff;
        wire [inst_sig_width+inst_exp_width:0] error_diff_pos;

        // gold - ans
        DW_fp_sub
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
            Err_S0 (.a(_softmax_w[gen_num]), .b(_your_task0_output[gen_num]), .z(error_diff), .rnd(3'd0));

        // // gold * _err_allow
        // DW_fp_mult
        // #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        //     Err_M0 (.a(_errRateAllow), .b(_prob[gen_num]), .z(bound), .rnd(3'd0));

        // // check |gold - ans| > gold * _err_allow
        // DW_fp_cmp
        // #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
        //     Err_C0 (.a(error_diff_pos), .b(bound), .agtb(_errRateFlag[gen_num]), .zctr(1'd0));

        // check |gold - ans| >  _err_allow
        DW_fp_cmp
        #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
            Err_C0 (.a(error_diff_pos), .b(_err_allow), .agtb(_err_flag_w[gen_num]), .zctr(1'd0));

        assign error_diff_pos = error_diff[inst_sig_width+inst_exp_width] ? {1'b0, error_diff[inst_sig_width+inst_exp_width-1:0]} : error_diff;
        assign _err_diff_w[gen_num] = error_diff_pos;
    end
endgenerate

// Task 1 : Convolution
generate
    for(gen_num=0 ; gen_num<NUM_OF_IMAGE_TASK1 ; gen_num=gen_num+1) begin
        for(gen_ch=1 ; gen_ch<=NUM_OF_KERNEL_CH ; gen_ch=gen_ch+1) begin
            for(gen_knl=1 ; gen_knl<=NUM_OF_KERNEL_IN_CH ; gen_knl=gen_knl+1) begin
                for(gen_row=0 ; gen_row<SIZE_OF_CONV ; gen_row=gen_row+1) begin
                    for(gen_col=0 ; gen_col<SIZE_OF_CONV ; gen_col=gen_col+1) begin
                        wire [inst_sig_width+inst_exp_width:0] a[NUM_OF_INPUT_OF_CONV-1:0];
                        wire [inst_sig_width+inst_exp_width:0] b[NUM_OF_INPUT_OF_CONV-1:0];
                        wire [inst_sig_width+inst_exp_width:0] conv_out;
                        // Input
                        for(gen_i=0 ; gen_i<NUM_OF_INPUT_OF_CONV ; gen_i=gen_i+1) begin
                            assign a[gen_i] = _pad[gen_num][gen_row+gen_i/SIZE_OF_KERNEL][gen_col+gen_i%SIZE_OF_KERNEL];
                            assign b[gen_i] = _kernel[gen_ch][gen_knl][gen_i/SIZE_OF_KERNEL][gen_i%SIZE_OF_KERNEL];
                        end
                        // IP
                        mac #(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch,NUM_OF_INPUT_OF_CONV)
                            c(
                                .in1(a), .in2(b), .out(conv_out)
                            );
                        assign _convolution1_w[gen_num][(gen_ch-1)*NUM_OF_KERNEL_CH+gen_knl][gen_row][gen_col] = conv_out;
                    end
                end
            end
        end
    end
endgenerate

generate
    for(gen_num=0 ; gen_num<NUM_OF_IMAGE_TASK1 ; gen_num=gen_num+1) begin : gb_num1
        for(gen_knl=1 ; gen_knl<=NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_CH ; gen_knl=gen_knl+1) begin : gb_knl1
            for(gen_row=0 ; gen_row<SIZE_OF_CONV ; gen_row=gen_row+1) begin : gb_row1
                for(gen_col=0 ; gen_col<SIZE_OF_CONV ; gen_col=gen_col+1) begin : gb_col1
                    wire [inst_sig_width+inst_exp_width:0] conv_sum_out;
                    if(gen_row===0 && gen_col===0) begin
                        
                    end
                    else if(gen_row===0 && gen_col===1) begin
                        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                            as(
                                .a(_convolution1_w[gen_num][gen_knl][gen_row][gen_col-1]),
                                .b(_convolution1_w[gen_num][gen_knl][gen_row][gen_col]),
                                .op(1'd0), .rnd(3'd0), .z(conv_sum_out)
                            );
                    end
                    else if(gen_row>0 && gen_col===0) begin
                        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                            as(
                                .a(gb_num1[gen_num].gb_knl1[gen_knl].gb_row1[gen_row-1].gb_col1[SIZE_OF_CONV-1].conv_sum_out),
                                .b(_convolution1_w[gen_num][gen_knl][gen_row][gen_col]),
                                .op(1'd0), .rnd(3'd0), .z(conv_sum_out)
                            );
                    end
                    else begin
                        DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance,inst_arch)
                            as(
                                .a(gb_num1[gen_num].gb_knl1[gen_knl].gb_row1[gen_row].gb_col1[gen_col-1].conv_sum_out),
                                .b(_convolution1_w[gen_num][gen_knl][gen_row][gen_col]),
                                .op(1'd0), .rnd(3'd0), .z(conv_sum_out)
                            );
                    end
                end
            end
            assign _convolution1_sum_w[gen_num][gen_knl-1] = 
                    gb_num1[gen_num].gb_knl1[gen_knl].gb_row1[SIZE_OF_CONV-1].gb_col1[SIZE_OF_CONV-1].conv_sum_out;
        end
    end
endgenerate

//=====================================================================
// Float Utility
//=====================================================================

function[inst_sig_width+inst_exp_width:0] generate_rand_input;
    input integer is_simple;

    reg[inst_sig_width+inst_exp_width:0] min_float_bits;
    reg[inst_sig_width+inst_exp_width:0] max_float_bits;
    real range;
    reg[inst_sig_width+inst_exp_width:0] range_float_bits;
    real rand_out;

    reg[inst_exp_width-1:0] random_exponent;
    reg[inst_sig_width+inst_exp_width:0] pool[7:0];
begin
    // +- 0, 0.5, 0.25, 0.125
    pool[0] = 32'h0000_0000;
    pool[1] = 32'h8000_0000;
    pool[2] = 32'h3F00_0000;
    pool[3] = 32'hBF00_0000;
    pool[4] = 32'h3E80_0000;
    pool[5] = 32'hBE80_0000;
    pool[6] = 32'h3E00_0000;
    pool[7] = 32'hBE00_0000;
    generate_rand_input = 0;

    if(is_simple) begin
        generate_rand_input = 0;
        generate_rand_input = pool[$urandom() % 8];
    end
    else begin
        if(MIN_RANGE_OF_INPUT > MAX_RANGE_OF_INPUT) begin
            $display("[ERROR] [PARAMETER] MIN_RANGE_OF_INPUT can't be larger than MAX_RANGE_OF_INPUT");
            $finish;
        end
        if(!is_valid_float_of_real(MIN_RANGE_OF_INPUT))begin
            $display("[ERROR] [PARAMETER] The minimum of input exceeds the defined range of float");
            $finish;
        end
        if(!is_valid_float_of_real(MAX_RANGE_OF_INPUT))begin
            $display("[ERROR] [PARAMETER] The maximum of input exceeds the defined range of float");
            $finish;
        end

        // min_float_bits = real_to_float_bits(MIN_RANGE_OF_INPUT);
        // max_float_bits = real_to_float_bits(MAX_RANGE_OF_INPUT);

        // // Randomize 
        // range = MAX_RANGE_OF_INPUT - MIN_RANGE_OF_INPUT;
        // range_float_bits = real_to_float_bits(range);
        // random_exponent = (PRECISION_OF_RANDOM_EXPONENT+(2**(inst_exp_width-1)-1));
        // // (-127) + random_exponent = PRECISION_OF_RANDOM_EXPONENT
        // // => random_exponent = PRECISION_OF_RANDOM_EXPONENT + 127
        // // => random_exponent = PRECISION_OF_RANDOM_EXPONENT + (2**(inst_exp_width-1)-1)
        // if(range_float_bits[inst_sig_width+:inst_exp_width] < random_exponent) begin
        //     $display("[ERROR] [PARAMETER] The PRECISION_OF_RANDOM_EXPONENT is larger than the expoent of your setting range(MAX_RANGE_OF_INPUT-MIN_RANGE_OF_INPUT)");
        //     $finish;
        // end

        // /*
        // Intuitive method
        //     @issue : not even distribution -> workaround : use a parameter to control precision by user
        // */
        // generate_rand_input = 0;
        // generate_rand_input[inst_sig_width+:inst_exp_width] = $urandom() % (range_float_bits[inst_sig_width+:inst_exp_width] + 1 - random_exponent) + random_exponent;
        // generate_rand_input[(inst_sig_width-1):0] = 
        //     (generate_rand_input[inst_sig_width+:inst_exp_width] !== range_float_bits[inst_sig_width+:inst_exp_width]) ? $urandom() % (2**inst_sig_width)
        //     : range_float_bits[(inst_sig_width-1):0] !== 0 ? $urandom() % (range_float_bits[(inst_sig_width-1):0])
        //     : 0;

        // // Add increment on minimal value
        // rand_out = float_bits_to_real(generate_rand_input);
        // rand_out = MIN_RANGE_OF_INPUT + rand_out;
        // generate_rand_input = real_to_float_bits(rand_out);

        rand_out = (real'($urandom()) / RAND_DIVISOR) * (MAX_RANGE_OF_INPUT - MIN_RANGE_OF_INPUT) + MIN_RANGE_OF_INPUT;
        generate_rand_input = real_to_float_bits(rand_out);
    end
end
endfunction

function is_valid_float_of_real;
    input real in;

    reg[real_sig_width+real_exp_width:0] real_bits;
    integer float_shift = -127;
    integer double_shift = -1023;
begin
    is_valid_float_of_real = 1;
    real_bits = $realtobits(in);
    if(real_bits[real_sig_width+:real_exp_width]+double_shift-float_shift > ((2**inst_exp_width)-1))begin
        $display("[WARNING] [FUNCTION] Exponent of real exceeds the defined range of float ( %d )", real_bits[real_sig_width+:real_exp_width]);
        is_valid_float_of_real = 0;
    end
end endfunction

function [inst_sig_width+inst_exp_width:0] real_to_float_bits;
    input real in;

    reg[real_sig_width+real_exp_width:0] real_bits;
    integer float_shift = -127;
    integer double_shift = -1023;
begin
    real_bits = $realtobits(in);
    if(!is_valid_float_of_real(in))begin
        $display("[ERROR] [FUNCTION] Exponent of real exceeds the defined range of float");
        $finish;
    end
    // sign
    real_to_float_bits[inst_sig_width+inst_exp_width]  = real_bits[real_sig_width+real_exp_width];
    // exponent
    real_to_float_bits[inst_sig_width+:inst_exp_width] = real_bits[real_sig_width+:real_exp_width]+double_shift-float_shift;
    // mantissa(fraction)
    real_to_float_bits[0+:inst_sig_width]              = real_bits[(real_sig_width-1)-:inst_sig_width];
end endfunction

function real float_bits_to_real;
    input reg[inst_sig_width+inst_exp_width:0] in;

    reg[real_sig_width+real_exp_width:0] real_bits;
    integer float_shift = -127;
    integer double_shift = -1023;
begin
    real_bits = 0;
    // sign
    real_bits[real_sig_width+real_exp_width] = in[inst_sig_width+inst_exp_width];
    // exponent
    real_bits[real_sig_width+:real_exp_width] = in[inst_sig_width+:inst_exp_width]+float_shift-double_shift;
    // mantissa(fraction)
    real_bits[(real_sig_width-1)-:inst_sig_width] = in[0+:inst_sig_width];

    float_bits_to_real = (in === 'dx) ? 0.0/0.0 : $bitstoreal(real_bits);

end endfunction

//=====================================================================
// Display Utitlity
//=====================================================================
task display_full_seperator; begin
    // Full
    $system("printf '%*s\\n' `tput cols` '' | tr ' ' '='");
    // Half
    // $system("cols=`tput cols`; half=$((cols/2-6)); printf '%*s\\n' $half ''");
end endtask

//=====================================================================
// Dumper
//=====================================================================
// Input
matrix_3d_csv_dumper #(
    NUM_OF_IMAGE_TASK0-1,SIZE_OF_IMAGE-1,SIZE_OF_IMAGE-1,
    0,0,0,
    inst_sig_width,inst_exp_width) image_task0_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_IMAGE_TASK1-1,SIZE_OF_IMAGE-1,SIZE_OF_IMAGE-1,
    0,0,0,
    inst_sig_width,inst_exp_width) image_task1_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_IN_CH,SIZE_OF_KERNEL-1,SIZE_OF_KERNEL-1,
    1,0,0,
    inst_sig_width,inst_exp_width) kernel_dumper();

matrix_2d_csv_dumper #(
    NUM_OF_WEIGHT1-1,SIZE_OF_WEIGHT1-1,
    0,0,
    inst_sig_width,inst_exp_width,
    "#", " wght") weight1_dumper();

matrix_1d_csv_dumper #(
    NUM_OF_BIAS1-1,
    0,
    inst_sig_width,inst_exp_width,
    "Bias1"
) bias1_dumper();

matrix_2d_csv_dumper #(
    NUM_OF_WEIGHT2-1,SIZE_OF_WEIGHT2-1,
    0,0,
    inst_sig_width,inst_exp_width,
    "#", " wght") weight2_dumper();

matrix_1d_csv_dumper #(
    NUM_OF_BIAS2-1,
    0,
    inst_sig_width,inst_exp_width,
    "Bias2"
) bias2_dumper();

//-------------------------------------------------------------

// Output : task 0
matrix_3d_csv_dumper #(
    MAX_NUM_OF_IMAGE-1,SIZE_OF_PAD-1,SIZE_OF_PAD-1,
    0,0,0,
    inst_sig_width,inst_exp_width) pad0_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_IN_CH,SIZE_OF_CONV-1,SIZE_OF_CONV-1,
    1,0,0,
    inst_sig_width,inst_exp_width,"ch") conv0_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_CH-1,SIZE_OF_CONV-1,SIZE_OF_CONV-1,
    0,0,0,
    inst_sig_width,inst_exp_width) conv0_sum_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_CH-1,SIZE_OF_MAXPOOL-1,SIZE_OF_MAXPOOL-1,
    0,0,0,
    inst_sig_width,inst_exp_width) max_pool_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_CH-1,SIZE_OF_ACTIVATE-1,SIZE_OF_ACTIVATE-1,
    0,0,0,
    inst_sig_width,inst_exp_width) activation_dumper();

matrix_1d_csv_dumper #(
    NUM_OF_FULLY1-1,
    0,
    inst_sig_width,inst_exp_width,
    "Fully1 Sum") fully1_dumper();

matrix_1d_csv_dumper #(
    NUM_OF_FULLY1-1,
    0,
    inst_sig_width,inst_exp_width,
    "Fully1 Sum After Activation") fully1_activation_dumper();

matrix_1d_csv_dumper #(
    NUM_OF_FULLY2-1,
    0,
    inst_sig_width,inst_exp_width,
    "Fully2 Sum") fully2_dumper();

matrix_1d_csv_dumper #(
    SIZE_OF_SOFTMAX-1,
    0,
    inst_sig_width,inst_exp_width,
    "Softmax") softmax_dumper();

// Output : task 1
matrix_3d_csv_dumper #(
    NUM_OF_IMAGE_TASK1-1,SIZE_OF_PAD-1,SIZE_OF_PAD-1,
    0,0,0,
    inst_sig_width,inst_exp_width) pad1_dumper();

matrix_3d_csv_dumper #(
    NUM_OF_KERNEL_IN_CH*NUM_OF_KERNEL_CH,SIZE_OF_CONV-1,SIZE_OF_CONV-1,
    1,0,0,
    inst_sig_width,inst_exp_width) conv1_dumper();

matrix_1d_csv_dumper #(
    SIZE_OF_CONV_SUM-1,
    0,
    inst_sig_width,inst_exp_width,
    "Convolution1 Sum")  conv1_sum_dumper();

//-------------------------------------------------------------

task export_input_to_csv;
    input integer is_hex;

    integer file;
    integer channel,num,row,col;
begin
    if(is_hex === 1) file = $fopen(INPUT_HEX_CSV, "w");
    else file = $fopen(INPUT_FLOAT_CSV, "w");

    $fdisplay(file, "Pattern,%d,", pat);
    $fdisplay(file, "Task,%2d,", _task_number);
    $fwrite(file, "Mode,%2d,", _mode);
    if(_mode === 'd0)      $fwrite(file, "Replication,tanh,\n");
    else if(_mode === 'd1) $fwrite(file, "Replication,swish,\n");
    else if(_mode === 'd2) $fwrite(file, "Reflection,tanh,\n");
    else if(_mode === 'd3) $fwrite(file, "Reflection,swish,\n");
    $fwrite(file, "\n");

    // Image
    $fdisplay(file, "Image");
    if(_task_number === 'd0)
        image_task0_dumper.dump(file, is_hex, _img);
    else
        image_task1_dumper.dump(file, is_hex, _img[NUM_OF_IMAGE_TASK1-1:0]);
    $fwrite(file, "\n");

    // Kernel
    for(channel=1 ; channel<=NUM_OF_KERNEL_CH ; channel=channel+1) begin
        $fdisplay(file, "Kernel,ch%2d", channel);
        kernel_dumper.dump(file, is_hex, _kernel[channel]);
    end
    $fwrite(file, "\n");

    if(_task_number === 'd0) begin
        // Weight
        $fdisplay(file, "Weight1");
        weight1_dumper.dump(file,is_hex,_weight1);
        $fwrite(file, "\n");
        bias1_dumper.dump(file,is_hex,_bias1);
        $fdisplay(file, "\n");

        $fdisplay(file, "Weight2");
        weight2_dumper.dump(file,is_hex,_weight2);
        $fwrite(file, "\n");
        bias2_dumper.dump(file,is_hex,_bias2);
        $fwrite(file, "\n");
    end
    else begin
        // Capacity
        $fwrite(file, ",");
        for(num=0 ; num<NUM_OF_CAPACITY ; num=num+1) begin
            $fwrite(file, "%2d,", num);
        end
        $fwrite(file, "\n");
        $fwrite(file, "Capacity,");
        for(num=0 ; num<NUM_OF_CAPACITY ; num=num+1) begin
            if(is_hex === 1) $fwrite(file, "%8h,", _capacity[num]);
            else $fwrite(file, "%2d,", _capacity[num]);
        end
        $fwrite(file, "\n");
    end

    $fclose(file);
end endtask

task export_output_to_csv;
    input integer is_hex;

    integer file;
    integer channel,num,row,col;
begin
    if(is_hex === 1) file = $fopen(OUTPUT_HEX_CSV, "w");
    else file = $fopen(OUTPUT_FLOAT_CSV, "w");

    // Pad
    if(_mode === 'd0)      $fwrite(file, "Padding,Replication,\n");
    else if(_mode === 'd1) $fwrite(file, "Padding,Replication,\n");
    else if(_mode === 'd2) $fwrite(file, "Padding,Reflection,\n");
    else if(_mode === 'd3) $fwrite(file, "Padding,Reflection,\n");
    

    if(_task_number === 'd0) begin
        pad0_dumper.dump(file,is_hex,_pad);
        $fwrite(file, "\n");

        for(num=0 ; num<NUM_OF_KERNEL_CH ; num=num+1) begin
            $fdisplay(file, "Convolution0,Channel #%2d", num+1);
            conv0_dumper.dump(file, is_hex, _convolution0[num]);
        end
        $fwrite(file, "\n");

        $fdisplay(file, "Convolution0 Sum");
        conv0_sum_dumper.dump(file, is_hex, _convolution0_sum);
        $fwrite(file, "\n");

        $fdisplay(file, "Max Pool");
        max_pool_dumper.dump(file, is_hex, _max_pool);
        $fwrite(file, "\n");

        $fdisplay(file, "Activation");
        activation_dumper.dump(file, is_hex, _activation);
        $fwrite(file, "\n");

        // Fully 1
        fully1_dumper.dump(file, is_hex, _fully1);
        $fwrite(file, "\n");

        fully1_activation_dumper.dump(file, is_hex, _fully1_activated);
        $fwrite(file, "\n");

        // Fully 2
        fully2_dumper.dump(file, is_hex, _fully2);
        $fwrite(file, "\n");

        // Softmax
        softmax_dumper.dump(file, is_hex, _softmax);
        $fwrite(file, "\n");
    end
    else begin
        pad1_dumper.dump(file,is_hex,_pad[NUM_OF_IMAGE_TASK1-1:0]);
        $fwrite(file, "\n");

        for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
            $fdisplay(file, "Convolution1,Image #%2d", num);
            conv1_dumper.dump(file, is_hex, _convolution1[num]);
        end
        $fwrite(file, "\n");

        for(num=0 ; num<NUM_OF_IMAGE_TASK1 ; num=num+1) begin
            conv1_sum_dumper.dump(file, is_hex, _convolution1_sum[num]);
        end
        $fwrite(file, "\n");


        $fdisplay(file, "Select Channel,#%4b", _select_channels[0][_capacity[0]][SIZE_OF_CONV_SUM-1:0]);
        $fdisplay(file, "Sum,%f", _dp[0][_capacity[0]]);
        
    end

    $fclose(file);
end endtask

endmodule

//==========================================================================================================================================

module matrix_1d_csv_dumper
#(
    parameter end1 = 0,
    parameter start1 = 0,
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter name = ""
)();

parameter real_sig_width = 52; // verilog real (double)
parameter real_exp_width = 11; // verilog real (double)
integer idx1;

task dump; 
    input integer file;
    input is_hex;
    input [inst_sig_width+inst_exp_width:0] in[end1:start1];
begin
    $fwrite(file, ",");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "%2d,", idx1);
    end
    $fwrite(file, "\n");
    $fwrite(file, "%0s,", name);
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        if(is_hex === 1) $fwrite(file, "%8h,", in[idx1]);
        else $fwrite(file, "%f,", PATTERN.float_bits_to_real(in[idx1]));
    end
    $fwrite(file, "\n");
end endtask;

endmodule

module matrix_2d_csv_dumper
#(
    parameter end1 = 0,
    parameter end2 = 0,
    parameter start1 = 0,
    parameter start2 = 0,
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter prefix_col = "",
    parameter postfix_col = "",
    parameter prefix_row = "",
    parameter postfix_row = ""
)();

parameter real_sig_width = 52; // verilog real (double)
parameter real_exp_width = 11; // verilog real (double)
integer idx1,idx2;

task dump; 
    input integer file;
    input is_hex;
    input [inst_sig_width+inst_exp_width:0] in[end1:start1][end2:start2];
begin
    $fwrite(file, ",");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_col, idx1, postfix_col);
    end
    $fwrite(file, "\n");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        $fwrite(file, "%0s%2d%0s,", prefix_row, idx2, postfix_row);
        for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
            if(is_hex === 1) $fwrite(file, "%8h,", in[idx1][idx2]);
            else $fwrite(file, "%f,", PATTERN.float_bits_to_real(in[idx1][idx2]));
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
    parameter inst_sig_width = 23,
    parameter inst_exp_width = 8,
    parameter prefix = ""
)();

parameter real_sig_width = 52; // verilog real (double)
parameter real_exp_width = 11; // verilog real (double)
integer idx1,idx2,idx3;

task dump; 
    input integer file;
    input is_hex;
    input [inst_sig_width+inst_exp_width:0] in[end1:start1][end2:start2][end3:start3];
begin
    // file = $fopen(file_name, "a");
    for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
        $fwrite(file, "[%0s%2d],", prefix, idx1);
        // idx1 index
        for(idx3=start3 ; idx3<=end3 ; idx3=idx3+1) begin
            $fwrite(file, "%2d,", idx3);
        end
        $fwrite(file, ",");
    end
    $fwrite(file, "\n");
    for(idx2=start2 ; idx2<=end2 ; idx2=idx2+1) begin
        for(idx1=start1 ; idx1<=end1 ; idx1=idx1+1) begin
            // idx2 index and value
            $fwrite(file, "%2d,", idx2);
            for(idx3=start3 ; idx3<=end3 ; idx3=idx3+1) begin
                if(is_hex === 1) $fwrite(file, "%8h,", in[idx1][idx2][idx3]);
                else $fwrite(file, "%f,", PATTERN.float_bits_to_real(in[idx1][idx2][idx3]));
            end
            $fwrite(file, ",");
        end
        $fwrite(file, "\n");
    end
end endtask;

endmodule

//==========================================================================================================================================

//=====================================================================
// IP Utility
//=====================================================================
module mac
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0,
    parameter num_of_input = 9
)
(
    input  [inst_sig_width+inst_exp_width:0] in1[num_of_input-1:0],
    input  [inst_sig_width+inst_exp_width:0] in2[num_of_input-1:0],
    output [inst_sig_width+inst_exp_width:0] out
);
    initial begin
        if(num_of_input < 2) begin
            $display("[ERROR] [Parameter] The num_of_input can't be smaller than 2");
            $finish;
        end
    end
    genvar i;
    generate
        for(i=0 ; i<num_of_input ; i=i+1) begin : gen_conv_mult
            wire [inst_sig_width+inst_exp_width:0] _mult;
            DW_fp_mult#(inst_sig_width, inst_exp_width, inst_ieee_compliance)
                M0 (.a(in1[i]), .b(in2[i]), .rnd(3'd0), .z(_mult));
        end
    endgenerate
    generate
        for(i=1 ; i<num_of_input ; i=i+1) begin : gen_conv_add
            wire [inst_sig_width+inst_exp_width:0] _add;
            if(i==1) begin
                DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A0 (.a(gen_conv_mult[0]._mult), .b(gen_conv_mult[1]._mult),
                        .op(1'd0), .rnd(3'd0), .z(_add));
            end
            else begin
                DW_fp_addsub#(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A0 (.a(gen_conv_add[i-1]._add), .b(gen_conv_mult[i]._mult),
                        .op(1'd0), .rnd(3'd0), .z(_add));
            end
        end
        assign out = gen_conv_add[num_of_input-1]._add;
    endgenerate
endmodule

module findMinAndMax
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0,
    parameter num_of_input = 4
)
(
    input  [inst_sig_width+inst_exp_width:0] in[num_of_input-1:0],
    output [inst_sig_width+inst_exp_width:0] min, max
);
    initial begin
        if(num_of_input < 2) begin
            $display("[ERROR] [Parameter] The num_of_input can't be smaller than 2");
            $finish;
        end
    end
    genvar i;
    generate
        for(i=1 ; i<num_of_input ; i=i+1) begin : gen_comp
            wire [inst_sig_width+inst_exp_width:0] _min, _max;
            if(i===1) begin
                wire flag;
                DW_fp_cmp
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
                    C0 (.a(in[i-1]), .b(in[i]), .agtb(flag), .zctr(1'd0));

                assign _min = flag==1 ? in[i] : in[i-1];
                assign _max = flag==1 ? in[i-1] : in[i];
            end
            else begin
                wire flagMin, flagMax;
                DW_fp_cmp
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
                    Cmin (.a(gen_comp[i-1]._min), .b(in[i]), .agtb(flagMin), .zctr(1'd0));
                DW_fp_cmp
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance) 
                    Cmax (.a(gen_comp[i-1]._max), .b(in[i]), .agtb(flagMax), .zctr(1'd0));

                assign _min = flagMin==1 ? in[i] : gen_comp[i-1]._min;
                assign _max = flagMax==1 ? gen_comp[i-1]._max : in[i];
            end
        end
        assign min = gen_comp[num_of_input-1]._min;
        assign max = gen_comp[num_of_input-1]._max;
    endgenerate

endmodule

module sigmoid
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] float_gain2 = 32'hBF800000; // Activation -1.0
    wire [inst_sig_width+inst_exp_width:0] x_neg;
    wire [inst_sig_width+inst_exp_width:0] exp;
    wire [inst_sig_width+inst_exp_width:0] deno;

    DW_fp_mult // -x
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(float_gain2), .rnd(3'd0), .z(x_neg));
    
    DW_fp_exp // exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(x_neg), .z(exp));
    
    DW_fp_addsub // 1+exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(float_gain1), .b(exp), .op(1'd0), .rnd(3'd0), .z(deno));
    
    DW_fp_div // 1 / [1+exp(-x)]
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(float_gain1), .b(deno), .rnd(3'd0), .z(out));
endmodule

module swish
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] float_gain2 = 32'hBF800000; // Activation -1.0
    wire [inst_sig_width+inst_exp_width:0] x_neg;
    wire [inst_sig_width+inst_exp_width:0] exp;
    wire [inst_sig_width+inst_exp_width:0] deno;

    DW_fp_mult // -x
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(float_gain2), .rnd(3'd0), .z(x_neg));
    
    DW_fp_exp // exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(x_neg), .z(exp));
    
    DW_fp_addsub // 1+exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(float_gain1), .b(exp), .op(1'd0), .rnd(3'd0), .z(deno));
    
    DW_fp_div // 1 / [1+exp(-x)]
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(in), .b(deno), .rnd(3'd0), .z(out));
endmodule

module tanh
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] float_gain2 = 32'hBF800000; // Activation -1.0
    wire [inst_sig_width+inst_exp_width:0] x_neg;
    wire [inst_sig_width+inst_exp_width:0] exp_pos;
    wire [inst_sig_width+inst_exp_width:0] exp_neg;
    wire [inst_sig_width+inst_exp_width:0] nume;
    wire [inst_sig_width+inst_exp_width:0] deno;

    DW_fp_mult // -x
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(float_gain2), .rnd(3'd0), .z(x_neg));
    
    DW_fp_exp // exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(x_neg), .z(exp_neg));

    DW_fp_exp // exp(x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E1 (.a(in), .z(exp_pos));

    //

    DW_fp_addsub // exp(x)-exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(exp_pos), .b(exp_neg), .op(1'd1), .rnd(3'd0), .z(nume));

    DW_fp_addsub // exp(x)+exp(-x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A1 (.a(exp_pos), .b(exp_neg), .op(1'd0), .rnd(3'd0), .z(deno));

    DW_fp_div // [exp(x)-exp(-x)] / [exp(x)+exp(-x)]
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(nume), .b(deno), .rnd(3'd0), .z(out));

endmodule

module softmax
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0,
    parameter num_of_input = 3
)
(
    input  [inst_sig_width+inst_exp_width:0] in_z,
    input  [inst_sig_width+inst_exp_width:0] in[num_of_input-1:0],
    output [inst_sig_width+inst_exp_width:0] out
);
    initial begin
        if(num_of_input < 1) begin
            $display("[ERROR] [Parameter] The num_of_input can't be smaller than 1");
            $finish;
        end
    end
    genvar i;
    // exp(x)
    generate
        for(i=0 ; i<num_of_input ; i=i+1) begin : gen_exp
            wire[inst_sig_width+inst_exp_width:0] exp_pos;
            DW_fp_exp 
            #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
                E0 (.a(in[i]), .z(exp_pos));
        end
    endgenerate
    // sigma(exp(x))
    generate
        for(i=1 ; i<num_of_input ; i=i+1) begin : gen_exp_sum
            wire[inst_sig_width+inst_exp_width:0] exp_sum;
            if(i===1) begin
                DW_fp_addsub
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A0 (.a(gen_exp[i-1].exp_pos), .b(gen_exp[i].exp_pos), .op(1'd0), .rnd(3'd0), .z(exp_sum));
            end
            else begin
                DW_fp_addsub 
                #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
                    A0 (.a(gen_exp_sum[i-1].exp_sum), .b(gen_exp[i].exp_pos), .op(1'd0), .rnd(3'd0), .z(exp_sum));
            end
        end
    endgenerate
    // exp(in_z) / sigma(exp(x))
    wire[inst_sig_width+inst_exp_width:0] exp_pos_z;
    wire[inst_sig_width+inst_exp_width:0] res;
    DW_fp_exp 
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E0 (.a(in_z), .z(exp_pos_z));
    DW_fp_div
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0)
        D0 (.a(exp_pos_z), .b(gen_exp_sum[num_of_input-1].exp_sum), .rnd(3'd0), .z(res));
    assign out = res;
endmodule

module softplus
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] float_gain1 = 32'h3F800000; // Activation 1.0
    wire [inst_sig_width+inst_exp_width:0] exp_pos;
    wire [inst_sig_width+inst_exp_width:0] plus;
    wire [7:0] status;
    
    DW_fp_exp // exp(x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, inst_arch)
        E1 (.a(in), .z(exp_pos));

    DW_fp_addsub // 1+exp(x)
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        A0 (.a(float_gain1), .b(exp_pos), .op(1'd0), .rnd(3'd0), .z(plus));

    DW_fp_ln // ln(1+exp(x))
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance, 0, inst_arch)
        L0 (.a(plus), .status(status), .z(out));

endmodule

module relu
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    assign out = in[inst_sig_width+inst_exp_width] ? 0 : in;
endmodule

module leakyRelu
#(  parameter inst_sig_width       = 23,
    parameter inst_exp_width       = 8,
    parameter inst_ieee_compliance = 0,
    parameter inst_arch            = 0
)
(
    input  [inst_sig_width+inst_exp_width:0] in,
    output [inst_sig_width+inst_exp_width:0] out
);
    wire [inst_sig_width+inst_exp_width:0] one_percent_factor = 32'h3c23d70a; // 0.01
    wire [inst_sig_width+inst_exp_width:0] one_percent_of_value;

    DW_fp_mult // x*0.01
    #(inst_sig_width,inst_exp_width,inst_ieee_compliance)
        M0 (.a(in), .b(one_percent_factor), .rnd(3'd0), .z(one_percent_of_value));

    assign out = in[inst_sig_width+inst_exp_width] ? one_percent_of_value : in;
endmodule