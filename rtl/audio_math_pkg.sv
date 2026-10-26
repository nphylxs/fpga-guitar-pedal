package audio_math_pkg;
  function automatic logic signed [15:0] sat16(input logic signed [47:0] x);
    if (x > 48'sd32767) return 16'sh7fff;
    if (x < -48'sd32768) return 16'sh8000;
    return x[15:0];
  endfunction
endpackage
