package net.kroia.stockmarketbridge;

import net.minecraft.world.item.BlockItem;
import net.minecraft.world.item.Item;
import net.minecraft.world.level.block.Block;
import net.minecraft.world.level.block.SoundType;
import net.minecraft.world.level.block.entity.BlockEntityType;
import net.minecraft.world.level.block.state.BlockBehaviour;
import net.minecraft.world.level.material.MapColor;
import net.minecraftforge.eventbus.api.IEventBus;
import net.minecraftforge.registries.DeferredRegister;
import net.minecraftforge.registries.ForgeRegistries;
import net.minecraftforge.registries.RegistryObject;

public final class BridgeRegistry {
    private BridgeRegistry() {}

    public static final DeferredRegister<Block> BLOCKS =
            DeferredRegister.create(ForgeRegistries.BLOCKS, StockMarketBridge.MOD_ID);
    public static final DeferredRegister<Item> ITEMS =
            DeferredRegister.create(ForgeRegistries.ITEMS, StockMarketBridge.MOD_ID);
    public static final DeferredRegister<BlockEntityType<?>> BLOCK_ENTITIES =
            DeferredRegister.create(ForgeRegistries.BLOCK_ENTITY_TYPES, StockMarketBridge.MOD_ID);

    public static final RegistryObject<Block> TRADING_BRIDGE = BLOCKS.register("trading_bridge",
            () -> new TradingBridgeBlock(BlockBehaviour.Properties.of()
                    .mapColor(MapColor.METAL)
                    .strength(3.0f, 6.0f)
                    .sound(SoundType.METAL)));

    public static final RegistryObject<Item> TRADING_BRIDGE_ITEM = ITEMS.register("trading_bridge",
            () -> new BlockItem(TRADING_BRIDGE.get(), new Item.Properties()));

    public static final RegistryObject<BlockEntityType<TradingBridgeBlockEntity>> TRADING_BRIDGE_BE =
            BLOCK_ENTITIES.register("trading_bridge",
                    () -> BlockEntityType.Builder.of(TradingBridgeBlockEntity::new, TRADING_BRIDGE.get())
                            .build(null));

    public static void register(IEventBus bus) {
        BLOCKS.register(bus);
        ITEMS.register(bus);
        BLOCK_ENTITIES.register(bus);
    }
}
