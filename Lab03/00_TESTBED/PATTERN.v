`ifdef RTL
    `define CYCLE_TIME 40.0
`endif
`ifdef GATE
    `define CYCLE_TIME 40.0
`endif

module PATTERN (
    // Output
    rst_n,
    clk,
    in_valid,
    pt_num,
    in_x,
    in_y,
    // Input
    out_valid,
    out_x,
    out_y,
    drop_num
);

//=====================================================================
//   PORT DECLARATION          
//=====================================================================
output reg    rst_n;
output reg    clk;
output reg    in_valid;
output reg    [8:0]    pt_num;
output reg    [9:0]    in_x;
output reg    [9:0]    in_y;

input    out_valid;
input    [9:0]    out_x;
input    [9:0]    out_y;
input    [6:0]    drop_num;

//=====================================================================
//   PARAMETER & INTEGER DECLARATION
//=====================================================================
// vvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvvv
integer SEED = 54875487;
parameter DEBUG = 1; // show information in detail
integer NUM_OF_RANDOM_PATTERN = 1000; // Only supported in MODE = 1
parameter INPUT_FILE_NAME = "../00_TESTBED/input.txt";
parameter MODE = 1; // 0 : use input.txt, 1 : use random

// Graph
parameter GRAPH_SHIFT = 100;
parameter ROW_PX_OF_GRID = 100;
parameter COL_PX_OF_GRID = 100;
// ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^

parameter MAX_EXECUTION_CYCLE = 1000;
parameter MAX_NUM_OF_POINT = 500;
parameter MIN_NUM_OF_POINT = 4;
parameter MAX_OF_POINT = 2**$bits(in_x)-1;
parameter MAX_SIDE_OF_CONVEX_HULL = 128;

integer file;
integer total_pats;
integer pat;
integer total_points;
integer point_index;
integer execution_lat;
integer total_lat;
real CYCLE = `CYCLE_TIME;

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
//   ALGORITHM
//=====================================================================
// total_points -> control the number of points
// Original data
integer cur_x;
integer cur_y;
integer point_x[MAX_NUM_OF_POINT-1:0];
integer point_y[MAX_NUM_OF_POINT-1:0];

// Algorithm
integer hull_x[MAX_NUM_OF_POINT*2-1:0];
integer hull_y[MAX_NUM_OF_POINT*2-1:0];
integer hull_index[MAX_NUM_OF_POINT*2-1:0];
integer size_of_hull;
integer sorted_index[MAX_NUM_OF_POINT-1:0];
integer sorted_index_large_index[MAX_NUM_OF_POINT-1:0];
integer point_to_drop_index[MAX_NUM_OF_POINT-1:0]; // 'dx still in the graph

// Output
integer gold_drop_num;
integer gold_drop_x[MAX_NUM_OF_POINT-1:0];
integer gold_drop_y[MAX_NUM_OF_POINT-1:0];

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
    generate_new_pattern;

    for (pat=0 ; pat<total_pats ; pat=pat+1) begin
        clear_point_info;
        generate_new_point_set;
        for (point_index=0 ; point_index<total_points ; point_index=point_index+1) begin
            input_task;
            cal_task;
            wait_task;
            check_task;
        end
        dump_point_to_html;
    end
    pass_task;
end endtask

task generate_new_pattern;
    integer temp;
begin
    if (MODE == 0) begin
        file = $fopen(INPUT_FILE_NAME, "r"); 
        temp = $fscanf(file, "%d\n", total_pats);
    end
    else begin
        total_pats = NUM_OF_RANDOM_PATTERN;
    end

    if (DEBUG) begin
        display_full_seperator;
        if(MODE == 0)
            $display("      Current MODE  : %7d (get input from file)", MODE);
        else
            $display("      Current MODE  : %7d (randomly generate)", MODE);
        $display("      Total pattern : %7d", total_pats);
        display_full_seperator;
    end

end endtask

task reset_task; begin
    force clk = 0;
    rst_n = 1;
    in_valid = 0;
    pt_num = 'dx;
    in_x = 'dx;
    in_y = 'dx;

    void'($urandom(SEED));
    total_lat = 0;

    #(CYCLE/2.0) rst_n = 0;
    #(CYCLE/2.0) rst_n = 1;
    if (out_valid !== 0 || drop_num !== 0 || out_x !== 0 || out_y !== 0) begin
        display_full_seperator;
        $display("      Output signal should be 0 at %-12d ps  ", $time*1000);
        display_full_seperator;
        repeat(5) #(CYCLE);
        $finish;
    end
    #(CYCLE/2.0) release clk;
end endtask

task clear_point_info;
    integer i;
begin
    for(i=0 ; i<MAX_NUM_OF_POINT ; i=i+1) begin
        point_x[i] = 'dx;
        point_y[i] = 'dx;
        hull_x[i] = 'dx;
        hull_y[i] = 'dx;
        hull_index[i] = 'dx;
        sorted_index[i] = 'dx;
        point_to_drop_index[i] = 'dx;
    end
    size_of_hull = 0;
end endtask

task generate_new_point_set;
    integer temp;
begin
    if(MODE == 0) begin
        temp = $fscanf(file, "%d\n", total_points);
    end
    else begin
        total_points = ($urandom() % (MAX_NUM_OF_POINT-MIN_NUM_OF_POINT+1)) + MIN_NUM_OF_POINT;
        if (DEBUG) begin
            display_full_seperator;
            $display("      For #%4d - start to generate #%4d of points", pat, total_points);
            display_full_seperator;
        end
    end
    repeat(($urandom() % 3) + 1) @(negedge clk);
end endtask

task input_task;
    integer temp;
    integer cur_num_of_points;
begin
    // Store
    if (MODE==0)
        temp = $fscanf(file, "%d %d\n", cur_x, cur_y);
    else begin
        cur_num_of_points = point_index+1;
        cur_x = ($urandom() % (MAX_OF_POINT + 1));
        cur_y = ($urandom() % (MAX_OF_POINT + 1));
        point_x[point_index] = cur_x;
        point_y[point_index] = cur_y;
        
        if(cur_num_of_points === 3) begin
            while(
                is_colinear(
                    point_x[0], point_y[0],
                    point_x[1], point_y[1],
                    point_x[2], point_y[2]
                )
            ) begin
                if(DEBUG == 2) begin
                    $display("      The first 3 point are colinear -- regenerate");
                end
                cur_x = ($urandom() % (MAX_OF_POINT + 1));
                cur_y = ($urandom() % (MAX_OF_POINT + 1));
                point_x[point_index] = cur_x;
                point_y[point_index] = cur_y;
            end
        end
        else if(cur_num_of_points > 3) begin
            sorted_points;
            update_hull;
            while(size_of_hull > MAX_SIDE_OF_CONVEX_HULL) begin
                if(DEBUG == 2) begin
                    $display("      # of side of the convex hull is larger than %4d --- regenerate", MAX_SIDE_OF_CONVEX_HULL);
                end
                cur_x = ($urandom() % (MAX_OF_POINT + 1));
                cur_y = ($urandom() % (MAX_OF_POINT + 1));
                point_x[point_index] = cur_x;
                point_y[point_index] = cur_y;
            end
        end
    end
    point_x[point_index] = cur_x;
    point_y[point_index] = cur_y;

    // Propagate
    @(negedge clk);
    in_valid = 1;
    pt_num = point_index == 0 ? total_points : 'dx;
    in_x = cur_x;
    in_y = cur_y;
    @(negedge clk);

    in_valid = 0;
    pt_num = 'dx;
    in_x = 'dx;
    in_y = 'dx;
end endtask

task cal_task;
    integer cur_num_of_points;
begin
    sorted_points;
    cur_num_of_points = point_index+1;
    if(cur_num_of_points <= 3) begin
        gold_drop_num = 0;
        gold_drop_x[0] = 0;
        gold_drop_y[0] = 0;
    end
    else begin
        update_hull;
        discard_points;
    end
end endtask

task wait_task; begin
    execution_lat = -1;
    while (out_valid !== 1) begin
        if (drop_num !== 0 || out_x !== 0 || out_y !== 0) begin
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

    integer i;
    integer j;
    integer your_drop_x[MAX_NUM_OF_POINT-1:0];
    integer your_drop_y[MAX_NUM_OF_POINT-1:0];
    integer is_check[MAX_NUM_OF_POINT-1:0];
begin
    // Output point should be in any order
    _out_lat = 0;
    _max_out_lat = gold_drop_num == 0 ? 1 : gold_drop_num;
    while(out_valid === 1) begin
        if (_out_lat===_max_out_lat) begin
            display_full_seperator;
            $display("      Out cycles is more than %-2d at %-12d ps ", _max_out_lat, $time*1000);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
        your_drop_x[_out_lat] = out_x;
        your_drop_y[_out_lat] = out_y;
        if (drop_num !== gold_drop_num) begin
            display_full_seperator;
            dump_point_to_html;
            $display("      Output signal : drop_num is not correct");
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
        if (drop_num === 0 && (out_x !== 0 || out_y !== 0)) begin
            display_full_seperator;
            dump_point_to_html;
            $display("      Output signal : drop_num is zero, the out_x and out_y must be zero");
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
        _out_lat = _out_lat + 1;
        @(negedge clk);
    end

    for(i=0 ; i<gold_drop_num ; i=i+1) begin
        is_check[i] = 0;
    end
    for(i=0 ; i<gold_drop_num ; i=i+1) begin
        for(j=0 ; j<gold_drop_num ; j=j+1) begin
            if(your_drop_x[i] === gold_drop_x[j] ||
                your_drop_y[i] === gold_drop_y[j]) begin
                is_check[j] = 1;
            end
        end
    end
    for(i=0 ; i<gold_drop_num ; i=i+1) begin
        if(is_check[i] === 0) begin
            display_full_seperator;
            dump_point_to_html;
            $display("      Output is wrong");
            $display("      You lose the point");
            $display("      Drop X   : %4d", gold_drop_x[i]);
            $display("      Drop Y   : %4d", gold_drop_y[i]);
            display_full_seperator;
            repeat(5) @(negedge clk);
            $finish;
        end
    end

    if (_out_lat < _max_out_lat) begin
        display_full_seperator;
        $display("      Out cycles is less than %-2d at %-12d ps ", _max_out_lat, $time*1000);
        display_full_seperator;
        repeat(5) @(negedge clk);
        $finish;
    end

    total_lat = total_lat + execution_lat;
    $display("%0sPASS PATTERN NO.%4d/Point NO.%4d (%4d, %4d), %0sCycles: %3d%0s",txt_blue_prefix, pat, point_index, cur_x, cur_y, txt_green_prefix, execution_lat, reset_color);
end endtask

task pass_task; begin
    $fclose(file);
    display_full_seperator;
    $display("      Total Latency : %10d", total_lat);
    display_full_seperator;
    $display("\033[1;33m                `oo+oy+`                            \033[1;35m Congratulation!!! \033[1;0m                                   ");
    $display("\033[1;33m               /h/----+y        `+++++:             \033[1;35m PASS This Lab........Maybe \033[1;0m                          ");
    $display("\033[1;33m             .y------:m/+ydoo+:y:---:+o                                                                                      ");
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

//---------------------------------------------------------------------
// Andrew’s Monotone Chain Utility
//---------------------------------------------------------------------
task sorted_points;
    integer i;
    integer j;
    integer k;
    integer new_index1;
    integer new_index2;
    integer compare_value;
    integer tmp;
begin
    // Clear
    for(i=0 ; i<MAX_NUM_OF_POINT ; i=i+1) begin
        sorted_index[i] = 'dx;
        sorted_index_large_index[i] = 'dx;
    end
    for(i=0 ; i<=point_index ; i=i+1) begin
        sorted_index[i] = i;
        sorted_index_large_index[i] = i;
    end

    // Sorted
    for(i=0; i<point_index; i=i+1) begin
        for(j=0; j<point_index-i; j=j+1) begin
            new_index1 = sorted_index[j];
            new_index2 = sorted_index[j+1];
            compare_value = compare(point_x[new_index1], point_y[new_index1],
                                point_x[new_index2], point_y[new_index2]);
            if(compare_value === 1 ||
                ((point_x[new_index1] == point_x[new_index2] && point_y[new_index1] == point_y[new_index2]) && new_index1 > new_index2) ) begin
                tmp = sorted_index[j];
                sorted_index[j] = sorted_index[j+1];
                sorted_index[j+1] = tmp;
            end
        end
    end

    for(i=0; i<point_index; i=i+1) begin
        for(j=0; j<point_index-i; j=j+1) begin
            new_index1 = sorted_index_large_index[j];
            new_index2 = sorted_index_large_index[j+1];
            compare_value = compare(point_x[new_index1], point_y[new_index1],
                                point_x[new_index2], point_y[new_index2]);
            if(compare_value === 1 ||
                ((point_x[new_index1] == point_x[new_index2] && point_y[new_index1] == point_y[new_index2]) && new_index1 < new_index2) ) begin
                tmp = sorted_index_large_index[j];
                sorted_index_large_index[j] = sorted_index_large_index[j+1];
                sorted_index_large_index[j+1] = tmp;
            end
        end
    end


            

    if(DEBUG == 2) begin
        $display("[Sorted points by index]");
        for(i=0; i<=point_index; i=i+1) begin
            $display("sorted #%4d (%4d, %4d) -> original (%4d)",
                i, point_x[sorted_index[i]], point_y[sorted_index[i]], sorted_index[i]);
        end
        $display("");

        $display("[Sorted points by index (large index first)]");
        for(i=0; i<=point_index; i=i+1) begin
            $display("sorted #%4d (%4d, %4d) -> original (%4d)",
                i, point_x[sorted_index_large_index[i]], point_y[sorted_index_large_index[i]], sorted_index_large_index[i]);
        end
        $display("");
    end 
end endtask

// Update hull
task update_hull;
    integer cur_num_of_points;
    integer i;
    integer j;
    integer k;
    integer t;
    integer new_index;

    integer size_of_orig_hull;
    integer orig_hull_x[MAX_NUM_OF_POINT*2-1:0];
    integer orig_hull_y[MAX_NUM_OF_POINT*2-1:0];
    integer orig_hull_index[MAX_NUM_OF_POINT*2-1:0];
    integer min_orig_index[MAX_NUM_OF_POINT*2-1:0];
    integer valid[MAX_NUM_OF_POINT*2-1:0];
begin
    cur_num_of_points = point_index+1;
    k = 0;
    for(i=0 ; i<MAX_NUM_OF_POINT*2 ; i=i+1) begin
        orig_hull_x[i] = 'dx;
        orig_hull_y[i] = 'dx;
        orig_hull_index[i] = 'dx;
    end

    // Build lower hull
    for(i=0 ; i<cur_num_of_points ; i=i+1) begin
        new_index = sorted_index[i];
        while(k>=2 &&
            calc_cross(orig_hull_x[k-2], orig_hull_y[k-2],
                        orig_hull_x[k-1], orig_hull_y[k-1],
                        point_x[new_index], point_y[new_index]) <= 0 ) begin
            orig_hull_x[k-1] = 'dx;
            orig_hull_y[k-1] = 'dx;
            k=k-1;
        end
        orig_hull_x[k] = point_x[new_index];
        orig_hull_y[k] = point_y[new_index];
        k=k+1;
    end

    // Build upper hull
    t=k+1;
    for(i=cur_num_of_points-2 ; i>=0 ; i=i-1) begin
        new_index = sorted_index_large_index[i];
        while(k>=t &&
            calc_cross(orig_hull_x[k-2], orig_hull_y[k-2],
                        orig_hull_x[k-1], orig_hull_y[k-1],
                        point_x[new_index], point_y[new_index]) <= 0 ) begin
            orig_hull_x[k-1] = 'dx;
            orig_hull_y[k-1] = 'dx;
            k=k-1;
        end
        orig_hull_x[k] = point_x[new_index];
        orig_hull_y[k] = point_y[new_index];
        k=k+1;
    end
    size_of_orig_hull = k;

    // Clear duplicated hull coordinates
    for (i=0; i<size_of_orig_hull; i=i+1) begin
        min_orig_index[i] = 'h0fffffff;
    end
    for (i=0 ; i<size_of_orig_hull ; i=i+1) begin
        for (j=0 ; j<cur_num_of_points ; j=j+1) begin
            new_index = sorted_index[j];
            if ((point_x[new_index] === orig_hull_x[i]) &&
                (point_y[new_index] === orig_hull_y[i])) begin
                if (new_index < min_orig_index[i]) begin
                    min_orig_index[i] = new_index;
                end
            end
        end
        if (min_orig_index[i] === 'dx) begin
            min_orig_index[i] = -1;
        end
    end

    for (i=0; i<size_of_orig_hull; i=i+1) begin
        valid[i] = 1;
    end

    for (i=0 ; i<size_of_orig_hull ; i=i+1) begin
        if (valid[i]) begin
            for (j=i+1 ; j<size_of_orig_hull ; j=j+1) begin
                if (valid[j]) begin
                    if ((orig_hull_x[i] == orig_hull_x[j]) &&
                        (orig_hull_y[i] == orig_hull_y[j])) begin
                        if (min_orig_index[i] == -1 && min_orig_index[j] == -1) begin
                            valid[j] = 0;
                        end
                        else if (min_orig_index[i] == -1) begin
                            valid[i] = 0;
                        end
                        else if (min_orig_index[j] == -1) begin
                            valid[j] = 0;
                        end
                        else begin
                            if (min_orig_index[i] <= min_orig_index[j]) begin
                                valid[j] = 0;
                            end else begin
                                valid[i] = 0;
                            end
                        end
                    end
                end
            end
        end
    end

    // Update hull_index
    for (i=0 ; i<size_of_orig_hull ; i=i+1) begin
        if (valid[i]) begin
            orig_hull_index[i] = min_orig_index[i];
        end
        else begin
            orig_hull_index[i] = -1;
        end
    end

    size_of_hull = 0;
    for (i=0 ; i<size_of_orig_hull ; i=i+1) begin
        if (valid[i]) begin
            hull_x[size_of_hull] = orig_hull_x[i];
            hull_y[size_of_hull] = orig_hull_y[i];
            hull_index[size_of_hull] = orig_hull_index[i];
            size_of_hull = size_of_hull + 1;
        end
    end


    if(DEBUG == 2) begin
        $display("[Original convex hull]");
        $display("Num of hulls : %4d", size_of_orig_hull);
        for (i=0 ; i<size_of_orig_hull ; i=i+1) begin
            $display("#%4d (%4d, %4d) - index : %4d", i, orig_hull_x[i], orig_hull_y[i], orig_hull_index[i]);
        end
        $display("");

        $display("[Non-duplicated convex hull]");
        $display("Num of hulls : %4d", size_of_hull);
        for (i=0 ; i<size_of_hull ; i=i+1) begin
            $display("#%4d (%4d, %4d) - index : %4d", i, hull_x[i], hull_y[i], hull_index[i]);
        end
        $display("");
    end
end endtask;

// Discard points
task discard_points;
    integer i;
    integer j;
    integer is_hull;
begin
    if(DEBUG==2) begin
        $display("[Dicard points]");
        for(i=0; i<=point_index; i=i+1) begin
            if(DEBUG==2) begin
                $display("#%4d (%4d, %4d) -> is in convex hull %4d / is in the hull index %4d", i, point_x[i], point_y[i],
                    is_in_convex_hull(point_x[i], point_y[i]), index_is_already_in_hull_list(i));
            end
        end
        $display("");
    end
    gold_drop_num = 0;
    for(i=0 ; i<MAX_NUM_OF_POINT ; i=i+1) begin
        gold_drop_x[i] = 'dx;
        gold_drop_y[i] = 'dx;
    end
    for(i=0; i<=point_index; i=i+1) begin
        if(index_is_already_in_hull_list(i) === 0) begin
            if(point_to_drop_index[i] === 'dx) begin
                if(is_in_convex_hull(point_x[i], point_y[i])) begin
                    point_to_drop_index[i] = point_index;
                    gold_drop_x[gold_drop_num] = point_x[i];
                    gold_drop_y[gold_drop_num] = point_y[i];
                    gold_drop_num = gold_drop_num + 1;
                end
            end
        end
    end
    if(gold_drop_num === 0) begin
        gold_drop_x[gold_drop_num] = 0;
        gold_drop_y[gold_drop_num] = 0;
    end

    if(DEBUG == 2) begin
        $display("[Drop index for points]");
        $display("Num of drop : %4d", gold_drop_num);
        for(i=0; i<=point_index; i=i+1) begin
            $display("#%4d (%4d, %4d) -> drop index : %4d", i, point_x[i], point_y[i], point_to_drop_index[i]);
        end
        $display("");
    end
end endtask

// Sorted by x firstly, then y
function integer compare;
    input [$bits(in_x)-1:0] x1;
    input [$bits(in_x)-1:0] y1;
    input [$bits(in_x)-1:0] x2;
    input [$bits(in_x)-1:0] y2;
begin
    if(x1 > x2) begin
        compare = 1;
    end
    else if(x1 < x2) begin
        compare = 0;
    end
    else begin
        compare = (y1 > y2) ? 1 : 0;
    end
end endfunction

function integer calc_cross;
    input [$bits(in_x)-1:0] x0;
    input [$bits(in_x)-1:0] y0;
    input [$bits(in_x)-1:0] xa;
    input [$bits(in_x)-1:0] ya;
    input [$bits(in_x)-1:0] xb;
    input [$bits(in_x)-1:0] yb;
begin
    calc_cross = (xa-x0)*(yb-y0)-(ya-y0)*(xb-x0);
end endfunction

function integer is_colinear;
    input [$bits(in_x)-1:0] x1;
    input [$bits(in_x)-1:0] y1;
    input [$bits(in_x)-1:0] x2;
    input [$bits(in_x)-1:0] y2;
    input [$bits(in_x)-1:0] x3;
    input [$bits(in_x)-1:0] y3;
begin
    is_colinear = (((x2-x1)*(y3-y1)-(y2-y1)*(x3-x1)) == 0) ? 1 : 0;
end endfunction

function integer point_is_already_in_hull_list;
    input [$bits(in_x)-1:0] x;
    input [$bits(in_x)-1:0] y;
    integer i;
begin
    point_is_already_in_hull_list = 0;
    for (i=0 ; i<MAX_NUM_OF_POINT*2 ; i=i+1) begin
        if (hull_x[i] === x && hull_y[i] === y) begin
            point_is_already_in_hull_list = 1;
        end
    end
end endfunction

function integer index_is_already_in_hull_list;
    input integer in_index;
    integer i;
begin
    index_is_already_in_hull_list = 0;
    for(i=0; i<size_of_hull; i=i+1) begin
        if(hull_index[i] === in_index) begin
            index_is_already_in_hull_list = 1;
        end
    end
end endfunction

function integer is_in_convex_hull;
    input [$bits(in_x)-1:0] x;
    input [$bits(in_x)-1:0] y;

    integer stop_flag;
    integer i;
    integer sign;
    integer next_index;
    integer cross_value;
begin
    stop_flag = 0;
    sign = 0;
    is_in_convex_hull = 1;
    for(int i=0 ; i<size_of_hull ; i=i+1) begin
        if(stop_flag == 1) begin
            next_index = (i+1)%size_of_hull;
            cross_value = calc_cross(
                hull_x[i], hull_y[i],
                hull_x[next_index], hull_y[next_index],
                x, y
            );
            if(cross_value != 0)begin
                if(sign == 0) sign = (cross_value > 0) ? 1 : -1;
                else if((cross_value>0 && sign==-1) || (cross_value<0 && sign==1))
                    is_in_convex_hull = 0;
            end
        end
    end
end endfunction

//---------------------------------------------------------------------
// Dump Utility
//---------------------------------------------------------------------
task dump_point_to_html;
    integer html_file;
    integer index_file;
    integer i, j;
    integer panel_width;

    integer is_dump[MAX_NUM_OF_POINT-1:0];
begin
    // TODO:
    // Improve the readability for the coordinates
    index_file = $fopen("graph_index.txt", "w");

    // txt
    $fdisplay(index_file, "red : current point");
    $fdisplay(index_file, "green : current drop node (drop_index shouldn't be unknown)");
    $fdisplay(index_file, "( <x>, <y> ) : <point_index> <drop_index>\n");

    // txt
    for(i=0 ; i<=point_index ; i=i+1) begin
        if(point_x[i] !== 'dx && point_y[i] !== 'dx) begin
            if(point_to_drop_index[i] === 'dx)
                $fdisplay(index_file, "( %4d, %4d ) : %4d    x", point_x[i], point_y[i], i);
            else
                $fdisplay(index_file, "( %4d, %4d ) : %4d %4d", point_x[i], point_y[i], i, point_to_drop_index[i]);
        end
    end

    $fdisplay(index_file, "");
    $fdisplay(index_file, "Drop Num : %4d", gold_drop_num);
    $fdisplay(index_file, "( <drop x>, <drop y> )\n");
    for(i=0 ; i<gold_drop_num ; i=i+1) begin
        $fdisplay(index_file, "( %4d, %4d )", gold_drop_x[i], gold_drop_y[i]);
    end



    $fclose(index_file);

    // HTML file
    html_file = $fopen("graph.html", "w");
    panel_width = (MAX_OF_POINT+1)+GRAPH_SHIFT;
    // HTML header
    $fwrite(html_file, "<!DOCTYPE html>\n<html>\n<head>\n");
    $fwrite(html_file, "<style>\n");
    $fwrite(html_file, ".point {\n");
    $fwrite(html_file, "  position: absolute;\n");
    $fwrite(html_file, "  width: 6px;\n");
    $fwrite(html_file, "  height: 6px;\n");
    $fwrite(html_file, "  border-radius: 50%%;\n");
    $fwrite(html_file, "  transform: translate(-3px,-3px);\n");
    $fwrite(html_file, "}\n");
    $fwrite(html_file, "</style>\n</head>\n<body>\n");
    // 0~1023 => add GRAPH_SHIFT
    $fwrite(html_file, "<div style='position:relative; width:%5dpx; height:%5dpx; border:1px solid black;'>\n", panel_width, panel_width);

    // HTML graph
    // grid (z-index:0)
    $fdisplay(html_file, "<svg width='%d' height='%d' style='position:absolute; left:0; top:0; z-index:0;'>", panel_width, panel_width);
    for (i=0; i<=panel_width; i=i+ROW_PX_OF_GRID) begin
        // vertical
        $fdisplay(html_file, "<line x1='%0d' y1='0' x2='%0d' y2='%d' stroke='#a09d9dff' stroke-width='1'/>",
            i+GRAPH_SHIFT/2, i+GRAPH_SHIFT/2, panel_width);
    end
    for (i=0; i<=panel_width; i=i+COL_PX_OF_GRID) begin
        // horizontal
        $fdisplay(html_file, "<line x1='0' y1='%0d' x2='%d' y2='%0d' stroke='#a09d9dff' stroke-width='1'/>",
            (panel_width-1)-(i+GRAPH_SHIFT/2), panel_width, (panel_width-1) - (i+GRAPH_SHIFT/2));
    end

    // boundary grid line
    // vertical
    $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%d' y2='%0d' stroke='#f3e309ff' stroke-width='1'/>",
        GRAPH_SHIFT/2, (panel_width-1)-(GRAPH_SHIFT/2), GRAPH_SHIFT/2, (panel_width-1)-(MAX_OF_POINT+GRAPH_SHIFT/2));
    $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%0d' y2='%0d' stroke='#f3e309ff' stroke-width='1'/>",
        MAX_OF_POINT+GRAPH_SHIFT/2, (panel_width-1)-(GRAPH_SHIFT/2), MAX_OF_POINT+GRAPH_SHIFT/2, (panel_width-1)-(MAX_OF_POINT+GRAPH_SHIFT/2));
    // horizontal
    $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%0d' y2='%0d' stroke='#f3e309ff' stroke-width='1'/>",
        GRAPH_SHIFT/2, (panel_width-1)-(GRAPH_SHIFT/2), MAX_OF_POINT+GRAPH_SHIFT/2, (panel_width-1)-(GRAPH_SHIFT/2));
    $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%0d' y2='%0d' stroke='#f3e309ff' stroke-width='1'/>",
        GRAPH_SHIFT/2, (panel_width-1)-(MAX_OF_POINT+GRAPH_SHIFT/2), MAX_OF_POINT+GRAPH_SHIFT/2, (panel_width-1)-(MAX_OF_POINT+GRAPH_SHIFT/2));

    // Hull line
    for(i=0 ; i<size_of_hull-1 ; i=i+1) begin
        $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%0d' y2='%0d' stroke='#0953f3ff' stroke-width='1'/>",
            hull_x[i]+GRAPH_SHIFT/2, (panel_width-1)-(hull_y[i]+GRAPH_SHIFT/2), 
            hull_x[i+1]+GRAPH_SHIFT/2, (panel_width-1)-(hull_y[i+1]+GRAPH_SHIFT/2));
    end
    $fdisplay(html_file, "<line x1='%0d' y1='%0d' x2='%0d' y2='%0d' stroke='#0953f3ff' stroke-width='1'/>",
        hull_x[size_of_hull-1]+GRAPH_SHIFT/2, (panel_width-1)-(hull_y[size_of_hull-1]+GRAPH_SHIFT/2), 
        hull_x[0]+GRAPH_SHIFT/2, (panel_width-1)-(hull_y[0]+GRAPH_SHIFT/2));

    $fdisplay(html_file, "</svg>");

    //----------------------------------------------------------------------------------------

    // draw (0,0) (0,1023) (1023,0) (1023,1023)
    for(i=0 ; i<=MAX_OF_POINT ; i=i+MAX_OF_POINT) begin
        for(j=0 ; j<=MAX_OF_POINT ; j=j+MAX_OF_POINT) begin
            $fwrite(html_file, "<div class='point' ");
            $fwrite(html_file, "style='left:%4dpx; ", i+GRAPH_SHIFT/2);
            $fwrite(html_file, "top:%4dpx; ", (panel_width-1) - (j+GRAPH_SHIFT/2));
            $fwrite(html_file, "background-color: #f3e309ff; ");
            $fwrite(html_file, "title='");
            $fwrite(html_file, "(x,y) = (%4d, %4d)'></div>\n", i, j);
        end
    end

    // Collect the index of the points which have the same coordinates
    for(i=0 ; i<MAX_NUM_OF_POINT ; i=i+1) begin
        is_dump[i] = 0;
    end
    // draw point
    for(i=0 ; i<=point_index ; i=i+1) begin
        if(point_x[i] !== 'dx && point_y[i] !== 'dx && is_dump[i] === 0) begin
            $fwrite(html_file, "<div class='point' ");
            $fwrite(html_file, "style='left:%4dpx; ", point_x[i]+GRAPH_SHIFT/2);
            $fwrite(html_file, "top:%4dpx; ", (panel_width-1) - (point_y[i]+GRAPH_SHIFT/2));
            // if(i==point_index)
            if(point_x[i]===cur_x && point_y[i]===cur_y) begin
                $fwrite(html_file, "background-color: #ff0000ff; ");
                $fwrite(html_file, "opacity: 0.5;' ");
            end
            else if(point_to_drop_index[i] === point_index)
                $fwrite(html_file, "background-color: #2bff00ff;' ");
            else if(point_to_drop_index[i] < point_index)
                $fwrite(html_file, "background-color: #696969ff;' ");
            else if(point_to_drop_index[i] === 'dx)
                $fwrite(html_file, "background-color: #000000ff;' ");
            $fwrite(html_file, "title='");
            $fwrite(html_file, "(x,y) = (%4d, %4d)\n(point_index, drop_index) = \n", point_x[i], point_y[i]);
            $fwrite(html_file, "(%3d, %3d)\n", i, point_to_drop_index[i]);
            for(j=i+1 ; j<=point_index ; j=j+1) begin
                if(point_x[i] == point_x[j] && point_y[i] == point_y[j]) begin
                    $fwrite(html_file, "(%3d, %3d)\n", j, point_to_drop_index[j]);
                    is_dump[j] = 1;
                end
            end
            $fwrite(html_file, "'>");
            $fwrite(html_file, "</div>\n");
        end
    end

    // HTML done
    $fwrite(html_file, "</div>\n</body>\n</html>");

    $fclose(html_file);
end endtask

//---------------------------------------------------------------------
// Display Utitlity
//---------------------------------------------------------------------
task display_full_seperator; begin
    // Full
    $system("printf '%*s\\n' `tput cols` '' | tr ' ' '='");
    // Half
    // $system("cols=`tput cols`; half=$((cols/2-6)); printf '%*s\\n' $half ''");
end endtask

endmodule