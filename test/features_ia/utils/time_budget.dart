/// Time budget for the tests that guard against catastrophic regex backtracking.
///
/// The bug they catch takes seconds or minutes on a large input; a linear pass takes a few
/// milliseconds. 500 ms keeps that difference obvious while a busy machine (emulator, parallel
/// suites) can still slow a correct pass down tenfold without failing the test.
const kLinearTimeBudgetMs = 500;
