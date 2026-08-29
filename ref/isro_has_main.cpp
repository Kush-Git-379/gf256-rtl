#include <cstdint>
#include <iostream>
#include <fstream>
#include <vector>
#include <bitset>
#include <iomanip>

using namespace std;

const int N = 255;
const int K = 32;
const int PAGE_BITS = 424;
const int PAGE_SYMBOLS = 53;

// =====================================================
// GF(256)
// Primitive polynomial:
// x^8 + x^4 + x^3 + x^2 + 1
// =====================================================

int gf_exp[512];
int gf_log[256];

void init_gf() {
    int x = 1;

    for(int i=0;i<255;i++) {
        gf_exp[i] = x;
        gf_log[x] = i;

        x <<= 1;

        if(x & 0x100)
            x ^= 0x11D;
    }

    for(int i=255;i<512;i++)
        gf_exp[i] = gf_exp[i-255];

    gf_log[0] = -1;
}

uint8_t gf_add(uint8_t a, uint8_t b) {
    return a ^ b;
}

uint8_t gf_mul(uint8_t a, uint8_t b) {

    if(a == 0 || b == 0)
        return 0;

    return gf_exp[gf_log[a] + gf_log[b]];
}

uint8_t gf_inv(uint8_t a) {

    if(a == 0) {
        cerr << "Inverse of zero!" << endl;
        exit(1);
    }

    return gf_exp[255 - gf_log[a]];
}

// =====================================================
// Matrix Inversion over GF(256)
// =====================================================

vector<vector<uint8_t>> invertMatrix(vector<vector<uint8_t>> A) {

    int n = A.size();

    vector<vector<uint8_t>> I(n, vector<uint8_t>(n,0));

    for(int i=0;i<n;i++)
        I[i][i] = 1;

    for(int i=0;i<n;i++) {

        if(A[i][i] == 0) {

            int swapRow = -1;

            for(int r=i+1;r<n;r++) {
                if(A[r][i] != 0) {
                    swapRow = r;
                    break;
                }
            }

            if(swapRow == -1) {
                cerr << "Matrix not invertible!" << endl;
                exit(1);
            }

            swap(A[i], A[swapRow]);
            swap(I[i], I[swapRow]);
        }

        uint8_t pivotInv = gf_inv(A[i][i]);

        for(int j=0;j<n;j++) {
            A[i][j] = gf_mul(A[i][j], pivotInv);
            I[i][j] = gf_mul(I[i][j], pivotInv);
        }

        for(int r=0;r<n;r++) {

            if(r == i)
                continue;

            uint8_t factor = A[r][i];

            for(int c=0;c<n;c++) {

                A[r][c] =
                    gf_add(A[r][c],
                           gf_mul(factor, A[i][c]));

                I[r][c] =
                    gf_add(I[r][c],
                           gf_mul(factor, I[i][c]));
            }
        }
    }

    return I;
}

// =====================================================
// Read GMatrix
// =====================================================

vector<vector<uint8_t>> readGMatrix(string filename) {

    vector<vector<uint8_t>> G(255, vector<uint8_t>(32));

    ifstream file(filename);

    if(!file.is_open()) {
        cerr << "Cannot open GMatrix file!" << endl;
        exit(1);
    }

    for(int i=0;i<255;i++) {
        for(int j=0;j<32;j++) {

            int val;
            file >> val;

            G[i][j] = (uint8_t)val;
        }
    }

    file.close();

    return G;
}

// =====================================================
// Convert bits -> symbols
// =====================================================

vector<uint8_t> bitsToSymbols(string bits) {

    vector<uint8_t> symbols;

    for(int i=24;i<448;i+=8) {

        bitset<8> b(bits.substr(i,8));

        symbols.push_back((uint8_t)b.to_ulong());
    }

    return symbols;
}

// =====================================================
// Header Parsing
// =====================================================

int getBits(string bits, int start, int len) {

    int val = 0;

    for(int i=0;i<len;i++) {
        val = (val << 1) | (bits[start+i]-'0');
    }

    return val;
}

struct Header {

    int HASS;
    int MT;
    int MID;
    int MS;
    int PID;
};

Header parseHeader(string bits) {

    Header h;

    h.HASS = getBits(bits,0,2);

    h.MT = getBits(bits,4,2);

    h.MID = getBits(bits,6,5);

    h.MS = getBits(bits,11,5)+1;

    h.PID = getBits(bits,16,8);

    return h;
}

// =====================================================
// Main
// =====================================================

int main() {

    init_gf();

    // -------------------------------------------------
    // Read Generator Matrix
    // -------------------------------------------------

    auto G = readGMatrix("GMatrix.txt");

    // -------------------------------------------------
    // Read received 448 bits
    // -------------------------------------------------

    string hexInput;

cout << "Enter C/NAV Page HEX:\n";

getline(cin, hexInput);

// remove spaces
string cleanHex;

for(char c : hexInput) {
    if(c != ' ')
        cleanHex += c;
}

// convert hex -> binary
string bits = "";

for(char c : cleanHex) {

    switch(toupper(c)) {

        case '0': bits += "0000"; break;
        case '1': bits += "0001"; break;
        case '2': bits += "0010"; break;
        case '3': bits += "0011"; break;
        case '4': bits += "0100"; break;
        case '5': bits += "0101"; break;
        case '6': bits += "0110"; break;
        case '7': bits += "0111"; break;
        case '8': bits += "1000"; break;
        case '9': bits += "1001"; break;
        case 'A': bits += "1010"; break;
        case 'B': bits += "1011"; break;
        case 'C': bits += "1100"; break;
        case 'D': bits += "1101"; break;
        case 'E': bits += "1110"; break;
        case 'F': bits += "1111"; break;
    }
}

cout << "Total bits = " << bits.length() << endl;
for(int offset = 0; offset < 100; offset++) {

    string test = bits.substr(offset,24);

    int hass = getBits(test,0,2);
    int mt   = getBits(test,4,2);
    int mid  = getBits(test,6,5);
    int ms   = getBits(test,11,5)+1;
    int pid  = getBits(test,16,8);

    if(hass == 0 &&
       mt == 1 &&
       mid == 15 &&
       ms == 15 &&
       pid == 55) {
        

        cout << "\nFOUND HEADER AT OFFSET = "
             << offset << endl;

        cout << test << endl;

        break;
    }
}
    // -------------------------------------------------
    // Parse header
    // -------------------------------------------------
bits = bits.substr(14,448);
Header h = parseHeader(bits);
cout << bits.substr(0,24) << endl;
    cout << "\n===== HEADER =====\n";

    cout << "HASS : " << h.HASS << endl;
    cout << "MT   : " << h.MT << endl;
    cout << "MID  : " << h.MID << endl;
    cout << "MS   : " << h.MS << endl;
    cout << "PID  : " << h.PID << endl;

    // -------------------------------------------------
    // Convert payload into 53 symbols
    // -------------------------------------------------

    vector<uint8_t> wprime ={
132,123,199,73,235,125,113,116,
36,71,136,251,69,70,145,140,
0,39,42,235,193,84,146,204,
110,181,90,88,128,226,97,186,
227,23,26,35,221,11,229,98,
252,141,111,216,142,98,41,194,
158,125,140,153,223
};

    cout << "\nReceived Symbols:\n";

    for(auto x : wprime)
        cout << (int)x << " ";

    cout << endl;

    // -------------------------------------------------
    // Example:
    // Assume we already collected k pages
    // -------------------------------------------------

    int k = h.MS;

    vector<int> receivedPIDs(k);

    cout << "\nEnter " << k << " received PIDs:\n";

    for(int i=0;i<k;i++)
        cin >> receivedPIDs[i];

    // -------------------------------------------------
    // Build D matrix
    // -------------------------------------------------

    vector<vector<uint8_t>> D(k, vector<uint8_t>(k));

    for(int i=0;i<k;i++) {

        int pid = receivedPIDs[i];

        for(int j=0;j<k;j++) {

            D[i][j] = G[pid-1][j];
        }
    }

    // -------------------------------------------------
    // Print D
    // -------------------------------------------------

    cout << "\n===== D Matrix =====\n";

    for(int i=0;i<k;i++) {
        for(int j=0;j<k;j++) {
            cout << setw(4) << (int)D[i][j];
        }
        cout << endl;
    }

    // -------------------------------------------------
    // Invert D
    // -------------------------------------------------

    auto Dinv = invertMatrix(D);

    // -------------------------------------------------
    // Print Dinv
    // -------------------------------------------------

    cout << "\n===== D Inverse =====\n";

    for(int i=0;i<k;i++) {
        for(int j=0;j<k;j++) {
            cout << setw(4) << (int)Dinv[i][j];
        }
        cout << endl;
    }

    // -------------------------------------------------
    // Example decode
    // m' = Dinv * w'
    // -------------------------------------------------

    // =====================================================
// ALL 15 RECEIVED PAGES
// =====================================================

vector<vector<uint8_t>> pages = {

{
132,123,199,73,235,125,113,116,36,71,136,
251,69,70,145,140,0,39,42,235,193,84,146,
204,110,181,90,88,128,226,97,186,227,23,
26,35,221,11,229,98,252,141,111,216,142,
98,41,194,158,125,140,153,223
},

{
52,154,227,99,77,33,11,173,50,147,166,
127,182,33,1,233,221,84,48,123,198,121,
237,105,155,213,12,174,174,197,100,133,
243,248,22,84,12,174,206,164,198,22,146,
238,91,24,202,171,181,189,162,121,57
},

{
85,1,29,145,14,230,225,85,194,242,140,
77,215,250,214,40,200,226,106,5,171,215,
135,151,77,226,225,111,142,246,176,156,
0,215,18,228,41,8,34,151,24,174,236,
105,28,5,39,243,194,63,128,181,19
},

{
44,163,27,35,21,83,238,106,156,122,59,
255,250,132,43,45,12,243,8,9,16,185,
194,2,126,136,115,220,237,47,141,167,
212,35,164,47,217,206,88,195,238,68,
125,44,175,49,177,138,4,213,165,186,120
},

{
55,190,96,216,35,121,141,182,26,28,152,
34,238,248,75,122,213,237,99,213,34,61,
152,173,145,204,133,143,64,117,119,92,
224,76,187,36,160,208,177,95,127,213,
58,214,134,44,121,248,82,63,169,191,75
},

{
187,28,69,29,89,4,160,228,22,185,43,
88,154,12,86,206,43,199,115,152,40,239,
11,192,73,228,145,24,154,41,63,49,
40,36,224,176,100,94,31,100,152,109,
111,135,185,118,207,58,18,247,59,144,33
},

{
117,25,72,154,251,194,111,69,202,191,253,
159,120,178,246,68,171,41,251,163,124,
202,254,239,152,25,2,5,204,223,192,
231,250,120,193,179,234,80,108,166,166,
167,210,195,99,135,159,118,132,143,164,128,36
},

{
143,12,156,52,139,203,193,61,89,3,53,
84,14,168,101,194,207,61,113,59,188,
39,200,99,26,41,88,222,211,134,178,
117,71,15,136,150,150,65,88,124,204,
128,23,28,51,166,204,221,251,63,53,44,190
},

{
203,226,36,10,145,27,54,129,243,142,43,
63,242,57,243,98,229,59,74,201,41,
44,96,199,124,97,197,70,118,78,134,
66,106,138,68,197,64,140,187,91,201,
10,138,135,16,254,109,113,144,220,128,204,93
},

{
29,55,158,167,195,223,144,158,158,116,87,
219,101,36,71,28,189,52,215,17,199,
92,176,139,74,132,108,3,25,126,46,
191,226,239,14,161,44,70,247,253,202,
246,58,36,35,29,77,144,52,14,217,139,221
},

{
122,57,40,21,48,65,99,21,77,50,204,
30,233,166,117,3,48,3,115,250,224,
78,143,108,245,144,255,199,147,114,161,
38,145,41,107,172,132,82,95,202,166,
152,75,83,88,143,25,25,186,202,151,159,222
},

{
125,19,56,207,112,92,184,147,239,181,113,
209,24,245,173,57,173,51,3,160,148,
255,182,92,140,168,146,194,234,61,53,
190,137,15,91,228,231,9,111,222,52,
62,205,189,90,185,129,222,74,19,154,94,29
},

{
161,204,117,222,253,61,201,66,207,106,21,
166,117,149,224,164,249,50,45,172,71,
205,29,87,112,81,177,95,215,130,214,
162,83,43,182,9,188,112,183,111,5,
174,231,176,103,151,117,7,232,167,19,33,234
},

{
207,147,205,21,140,244,31,178,149,173,157,
33,161,85,130,130,237,116,136,51,54,
137,106,123,126,234,208,57,145,34,116,
229,209,226,26,86,63,239,245,210,21,
211,61,189,43,85,215,103,160,170,234,163,56
},

{
215,200,167,19,210,166,18,96,224,77,5,
145,106,148,222,103,157,196,233,132,109,
61,229,187,163,152,17,62,27,210,42,
67,181,2,23,108,68,206,189,76,58,
39,164,43,254,9,87,41,18,228,135,212,165
}


};

// =====================================================
// Decode ALL 53 vertical words
// =====================================================

vector<vector<uint8_t>> decoded(k, vector<uint8_t>(53));

for(int col=0; col<53; col++) {

    vector<uint8_t> word(k);

    for(int row=0; row<k; row++) {
        word[row] = pages[row][col];
    }

    for(int i=0;i<k;i++) {

        uint8_t sum = 0;

        for(int j=0;j<k;j++) {

            sum = gf_add(
                    sum,
                    gf_mul(Dinv[i][j], word[j])
                  );
        }

        decoded[i][col] = sum;
    }
}

cout << "\n===== DECODED MESSAGE =====\n";

for(int i=0;i<k;i++) {

    for(int j=0;j<53;j++) {

        cout << setw(4)
             << (int)decoded[i][j];
    }

    cout << endl;
}
    return 0;
}
//fffc17b8de11ef1d27adf5c5d0911e23ed151a4630009cabaf05524b31bad56962038986eb8c5c688f742f958bf235bf623988a70a79f632677d0c4690000000
//55 56 57 58 59 174 175 176 187 188 239 240 241 252 253