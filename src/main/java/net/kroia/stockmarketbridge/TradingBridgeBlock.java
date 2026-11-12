package net.kroia.stockmarketbridge;

import net.minecraft.core.BlockPos;
import net.minecraft.network.chat.Component;
import net.minecraft.server.level.ServerPlayer;
import net.minecraft.world.InteractionHand;
import net.minecraft.world.InteractionResult;
import net.minecraft.world.entity.LivingEntity;
import net.minecraft.world.entity.player.Player;
import net.minecraft.world.item.ItemStack;
import net.minecraft.world.level.Level;
import net.minecraft.world.level.block.BaseEntityBlock;
import net.minecraft.world.level.block.RenderShape;
import net.minecraft.world.level.block.entity.BlockEntity;
import net.minecraft.world.level.block.state.BlockState;
import net.minecraft.world.phys.BlockHitResult;
import org.jetbrains.annotations.Nullable;

/**
 * Bloc "Trading Bridge" : posé par un joueur, il se lie à son compte BankSystem
 * et s'expose comme périphérique ComputerCraft.
 */
public class TradingBridgeBlock extends BaseEntityBlock {
    public TradingBridgeBlock(Properties properties) {
        super(properties);
    }

    @Override
    public RenderShape getRenderShape(BlockState state) {
        // BaseEntityBlock est INVISIBLE par défaut
        return RenderShape.MODEL;
    }

    @Nullable
    @Override
    public BlockEntity newBlockEntity(BlockPos pos, BlockState state) {
        return new TradingBridgeBlockEntity(pos, state);
    }

    @Override
    public void setPlacedBy(Level level, BlockPos pos, BlockState state,
                            @Nullable LivingEntity placer, ItemStack stack) {
        super.setPlacedBy(level, pos, state, placer, stack);
        if (level.isClientSide) return;
        if (placer instanceof ServerPlayer player
                && level.getBlockEntity(pos) instanceof TradingBridgeBlockEntity be) {
            be.setOwner(player.getUUID(), player.getGameProfile().getName());
            player.displayClientMessage(
                    Component.translatable("message.stockmarketbridge.bound", be.getOwnerName()), true);
        }
    }

    @Override
    public InteractionResult use(BlockState state, Level level, BlockPos pos, Player player,
                                 InteractionHand hand, BlockHitResult hit) {
        if (!level.isClientSide && level.getBlockEntity(pos) instanceof TradingBridgeBlockEntity be) {
            Component msg = be.hasOwner()
                    ? Component.translatable("message.stockmarketbridge.owner", be.getOwnerName())
                    : Component.translatable("message.stockmarketbridge.unbound");
            player.displayClientMessage(msg, true);
        }
        return InteractionResult.sidedSuccess(level.isClientSide);
    }
}
