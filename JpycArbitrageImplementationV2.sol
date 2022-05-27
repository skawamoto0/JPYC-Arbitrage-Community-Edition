// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IErc20 {
    function decimals() external pure returns(uint8);
    function balanceOf(address) external view returns(uint256);
    function transfer(address, uint256) external returns(bool);
    function approve(address, uint256) external returns(bool);
    function transferFrom(address, address, uint256) external returns(bool);
}

interface IQuickSwapRouter {
    function getAmountsOut(uint256, address[] calldata) external view returns(uint256[] memory);
    function swapExactTokensForTokens(uint256, uint256, address[] calldata, address, uint256) external returns(uint256[] memory);
}

struct UniswapExactInputSingle {
    address _0;
    address _1;
    uint24 _2;
    address _3;
    uint256 _4;
    uint256 _5;
    uint256 _6;
    uint160 _7;
}

interface IUniswapQuoter {
    function quoteExactInputSingle(address, address, uint24, uint256, uint160) external returns(uint256);
}

interface IUniswapRouter {
    function exactInputSingle(UniswapExactInputSingle calldata) external returns(uint256);
}

interface ICurvePool {
    function get_dy(int128, int128, uint256) external view returns(uint256);
    function exchange(int128, int128, uint256, uint256) external returns(uint256);
}

struct JarvisMint {
    address _0;
    uint256 _1;
    uint256 _2;
    uint256 _3;
    uint256 _4;
    address _5;
}

interface IJarvisPool {
    function mint(JarvisMint calldata) external returns(uint256, uint256);
    function redeem(JarvisMint calldata) external returns(uint256, uint256);
    function calculateFee(uint256) external view returns(uint256);
}

interface IJarvisAggregator {
    function latestRoundData() external view returns(uint80, int256, uint256, uint256, uint80);
    function decimals() external view returns(uint8);
}

contract JpycArbitrageImplementationV2 {
    address internal immutable self;
    IErc20 internal constant jpycv2 = IErc20(0x431D5dfF03120AFA4bDf332c61A6e1766eF37BDB);
    IErc20 internal constant jjpy = IErc20(0x8343091F2499FD4b6174A46D067A920a3b851FF9);
    IErc20 internal constant usdc = IErc20(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174);
    IQuickSwapRouter internal constant routerQuickSwap = IQuickSwapRouter(0xa5E0829CaCEd8fFDD4De3c43696c57F7D7A678ff);
    IUniswapQuoter internal constant quoterUniswap = IUniswapQuoter(0xb27308f9F90D607463bb33eA1BeBb41C27CE5AB6);
    IUniswapRouter internal constant routerUniswap = IUniswapRouter(0xE592427A0AEce92De3Edee1F18E0157C05861564);
    ICurvePool internal constant poolCurveV2 = ICurvePool(0xaA91CDD7abb47F821Cf07a2d38Cc8668DEAf1bdc);
    IJarvisPool internal constant poolJarvis = IJarvisPool(0x6cA82a7E54053B102e7eC452788cC19204e831de);
    IJarvisAggregator internal constant aggregatorJarvis = IJarvisAggregator(0xD647a6fC9BC6402301583C91decC5989d8Bc382D);
    address internal constant derivativeJarvis = 0x2076648e2D9d452D55f4252CBa9b162A1850Db48;
    mapping(address => bool) internal owners;
    mapping(address => bool) internal callers;
    modifier restricted {
        require(address(this) == self);
        require(owners[msg.sender]);
        _;
    }
    modifier called {
        require(address(this) == self);
        require(callers[msg.sender]);
        _;
    }
    modifier exclusive {
        require(msg.sender == address(this));
        _;
    }
    constructor() {
        self = address(this);
        owners[msg.sender] = true;
        jpycv2.approve(address(routerQuickSwap), type(uint256).max);
        jpycv2.approve(address(routerUniswap), type(uint256).max);
        jpycv2.approve(address(poolCurveV2), type(uint256).max);
        jjpy.approve(address(routerUniswap), type(uint256).max);
        jjpy.approve(address(poolCurveV2), type(uint256).max);
        jjpy.approve(address(poolJarvis), type(uint256).max);
        usdc.approve(address(routerQuickSwap), type(uint256).max);
        usdc.approve(address(routerUniswap), type(uint256).max);
        usdc.approve(address(poolJarvis), type(uint256).max);
    }
    function addOwner(address[] calldata addresses) public restricted {
        uint256 i;
        for(i = 0; i < addresses.length; i++) {
            owners[addresses[i]] = true;
        }
    }
    function removeOwner(address[] calldata addresses) public restricted {
        uint256 i;
        for(i = 0; i < addresses.length; i++) {
            owners[addresses[i]] = false;
        }
    }
    function call(address payable target, bytes calldata arguments) public restricted returns(bytes memory) {
        bytes memory a;
        (, a) = target.call(arguments);
        return a;
    }
    function read(bytes32 slot) public view restricted returns(bytes32) {
        bytes32 a;
        assembly {
            a := sload(slot)
        }
        return a;
    }
    function write(bytes32 slot, bytes32 data) public restricted {
        assembly {
            sstore(slot, data)
        }
    }
    function addCaller(address[] calldata addresses) public restricted {
        uint256 i;
        for(i = 0; i < addresses.length; i++) {
            callers[addresses[i]] = true;
        }
    }
    function removeCaller(address[] calldata addresses) public restricted {
        uint256 i;
        for(i = 0; i < addresses.length; i++) {
            callers[addresses[i]] = false;
        }
    }
    function checkArbitrage(uint256 amount) public called returns(uint256, uint256) {
        uint256 route0;
        uint256 amountOut0;
        uint256 route1;
        uint256 amountOut1;
        uint256 amountIn;
        uint256 amountOut;
        uint256 i;
        route0 = 0;
        amountIn = amount;
        amountOut0 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateJpycV2ToJjpy(i, amountIn);
            if(amountOut > amountOut0) {
                amountOut0 = amountOut;
                route0 = (route0 & ~(uint256(1) << 1)) | (i << 1);
            }
        }
        amountIn = amountOut0;
        amountOut0 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateJjpyToUsdc(i, amountIn);
            if(amountOut > amountOut0) {
                amountOut0 = amountOut;
                route0 = (route0 & ~(uint256(1) << 2)) | (i << 2);
            }
        }
        amountIn = amountOut0;
        amountOut0 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateUsdcToJpycV2(i, amountIn);
            if(amountOut > amountOut0) {
                amountOut0 = amountOut;
                route0 = (route0 & ~(uint256(1) << 3)) | (i << 3);
            }
        }
        route1 = 1;
        amountIn = amount;
        amountOut1 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateJpycV2ToUsdc(i, amountIn);
            if(amountOut > amountOut1) {
                amountOut1 = amountOut;
                route1 = (route1 & ~(uint256(1) << 1)) | (i << 1);
            }
        }
        amountIn = amountOut1;
        amountOut1 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateUsdcToJjpy(i, amountIn);
            if(amountOut > amountOut1) {
                amountOut1 = amountOut;
                route1 = (route1 & ~(uint256(1) << 2)) | (i << 2);
            }
        }
        amountIn = amountOut1;
        amountOut1 = 0;
        for(i = 0; i < 2; i++) {
            amountOut = rateJjpyToJpycV2(i, amountIn);
            if(amountOut > amountOut1) {
                amountOut1 = amountOut;
                route1 = (route1 & ~(uint256(1) << 3)) | (i << 3);
            }
        }
        if(amountOut0 >= amountOut1) {
            return (amountOut0, route0);
        }
        return (amountOut1, route1);
    }
    function checkArbitrageLimited(uint256 amount, uint256 enable0, uint256 enable1) internal returns(uint256, uint256) {
        uint256 route0;
        uint256 amountOut0;
        uint256 route1;
        uint256 amountOut1;
        uint256 amountIn;
        uint256 amountOut;
        uint256 i;
        route0 = 0;
        amountOut0 = 0;
        if(enable0 != 0) {
            amountOut0 = rateJpycV2ToJjpy(0, amount);
            amountOut0 = rateJjpyToUsdc(0, amountOut0);
            amountIn = amountOut0;
            amountOut0 = 0;
            for(i = 0; i < 2; i++) {
                amountOut = rateUsdcToJpycV2(i, amountIn);
                if(amountOut > amountOut0) {
                    amountOut0 = amountOut;
                    route0 = (route0 & ~(uint256(1) << 3)) | (i << 3);
                }
            }
        }
        route1 = 1;
        amountOut1 = 0;
        if(enable1 != 0) {
            amountIn = amount;
            for(i = 0; i < 2; i++) {
                amountOut = rateJpycV2ToUsdc(i, amountIn);
                if(amountOut > amountOut1) {
                    amountOut1 = amountOut;
                    route1 = (route1 & ~(uint256(1) << 1)) | (i << 1);
                }
            }
            amountOut1 = rateUsdcToJjpy(0, amountOut1);
            amountOut1 = rateJjpyToJpycV2(0, amountOut1);
        }
        if(amountOut0 >= amountOut1) {
            return (amountOut0, route0);
        }
        return (amountOut1, route1);
    }
    function arbitrage(uint256 amount, uint256 minimum, uint256 route, uint256 loop) public called {
        uint256 balance;
        uint256 profitOld;
        uint256 profit;
        if((route & (1 << 4)) != 0) {
            if((route & 1) == 0) {
                (balance, route) = checkArbitrageLimited(amount, 1, 0);
            }
            else {
                (balance, route) = checkArbitrageLimited(amount, 0, 1);
            }
            require(balance >= amount);
        }
        balance = jpycv2.balanceOf(msg.sender);
        jpycv2.transferFrom(msg.sender, address(this), amount);
        profitOld = 0;
        while(loop > 0) {
            try JpycArbitrageImplementationV2(this).exchange(amount, route) {
            }
            catch {
                break;
            }
            profit = jpycv2.balanceOf(address(this)) - amount;
            amount += profit;
            if(profit <= profitOld / 2) {
                break;
            }
            profitOld = profit;
            loop--;
        }
        require(amount >= minimum);
        jpycv2.transfer(msg.sender, amount);
        require(jpycv2.balanceOf(msg.sender) >= balance);
    }
    function exchange(uint256 amount, uint256 route) external exclusive {
        if((route & 1) == 0) {
            exchangeJpycV2ToJjpy((route & (1 << 1)) >> 1);
            exchangeJjpyToUsdc((route & (1 << 2)) >> 2);
            exchangeUsdcToJpycV2((route & (1 << 3)) >> 3);
        }
        else {
            exchangeJpycV2ToUsdc((route & (1 << 1)) >> 1);
            exchangeUsdcToJjpy((route & (1 << 2)) >> 2);
            exchangeJjpyToJpycV2((route & (1 << 3)) >> 3);
        }
        require(jpycv2.balanceOf(address(this)) >= amount);
    }
    function rateJpycV2ToUsdc(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try routerQuickSwap.getAmountsOut(amount, addressArray(address(jpycv2), address(usdc))) returns(uint256[] memory a) {
                return a[1];
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(jpycv2), address(usdc), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeJpycV2ToUsdc(uint256 route) internal {
        if(route == 0) {
            routerQuickSwap.swapExactTokensForTokens(jpycv2.balanceOf(address(this)), 0, addressArray(address(jpycv2), address(usdc)), address(this), block.timestamp);
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(jpycv2), address(usdc), 500, address(this), block.timestamp, jpycv2.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function rateUsdcToJpycV2(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try routerQuickSwap.getAmountsOut(amount, addressArray(address(usdc), address(jpycv2))) returns(uint256[] memory a) {
                return a[1];
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(usdc), address(jpycv2), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeUsdcToJpycV2(uint256 route) internal {
        if(route == 0) {
            routerQuickSwap.swapExactTokensForTokens(usdc.balanceOf(address(this)), 0, addressArray(address(usdc), address(jpycv2)), address(this), block.timestamp);
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(usdc), address(jpycv2), 500, address(this), block.timestamp, usdc.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function rateJjpyToJpycV2(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try poolCurveV2.get_dy(0, 1, amount) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(jjpy), address(jpycv2), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeJjpyToJpycV2(uint256 route) internal {
        if(route == 0) {
            poolCurveV2.exchange(0, 1, jjpy.balanceOf(address(this)), 0);
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(jjpy), address(jpycv2), 500, address(this), block.timestamp, jjpy.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function rateJpycV2ToJjpy(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try poolCurveV2.get_dy(1, 0, amount) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(jpycv2), address(jjpy), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeJpycV2ToJjpy(uint256 route) internal {
        if(route == 0) {
            poolCurveV2.exchange(1, 0, jpycv2.balanceOf(address(this)), 0);
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(jpycv2), address(jjpy), 500, address(this), block.timestamp, jpycv2.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function rateUsdcToJjpy(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try aggregatorJarvis.latestRoundData() returns(uint80, int256 a, uint256, uint256, uint80) {
                return ((amount * amount / (amount + poolJarvis.calculateFee(amount))) * (10 ** jjpy.decimals()) / (10 ** usdc.decimals())) * (10 ** aggregatorJarvis.decimals()) / uint256(a);
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(usdc), address(jjpy), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeUsdcToJjpy(uint256 route) internal {
        if(route == 0) {
            poolJarvis.mint(JarvisMint(derivativeJarvis, 0, usdc.balanceOf(address(this)), 2000000000000000, block.timestamp, address(this)));
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(usdc), address(jjpy), 500, address(this), block.timestamp, usdc.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function rateJjpyToUsdc(uint256 route, uint256 amount) internal returns(uint256) {
        if(amount == 0) {
            return 0;
        }
        if(route == 0) {
            try aggregatorJarvis.latestRoundData() returns(uint80, int256 a, uint256, uint256, uint80) {
                return ((amount - poolJarvis.calculateFee(amount)) * (10 ** usdc.decimals()) / (10 ** jjpy.decimals())) * uint256(a) / (10 ** aggregatorJarvis.decimals());
            }
            catch {
            }
        }
        if(route == 1) {
            try quoterUniswap.quoteExactInputSingle(address(jjpy), address(usdc), 500, amount, 0) returns(uint256 a) {
                return a;
            }
            catch {
            }
        }
        return 0;
    }
    function exchangeJjpyToUsdc(uint256 route) internal {
        if(route == 0) {
            poolJarvis.redeem(JarvisMint(derivativeJarvis, jjpy.balanceOf(address(this)), 0, 2000000000000000, block.timestamp, address(this)));
            return;
        }
        if(route == 1) {
            routerUniswap.exactInputSingle(UniswapExactInputSingle(address(jjpy), address(usdc), 500, address(this), block.timestamp, jjpy.balanceOf(address(this)), 0, 0));
            return;
        }
        revert();
    }
    function addressArray(address _0, address _1) internal pure returns(address[] memory) {
        address[] memory a;
        a = new address[](2);
        a[0] = _0;
        a[1] = _1;
        return a;
    }
}
